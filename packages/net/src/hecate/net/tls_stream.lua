-- TlsStream: a `Stream` that encrypts over another `Stream` (ADR 0021). The native session is
-- sans-IO (`rustls`): this class moves bytes between it and the inner stream, so every
-- suspension happens in the inner stream and the reactor stays in charge of I/O.
--
-- Sending. Ciphertext reaches the inner stream through one writer at a time (`_send`). `write`
-- and `shutdown` hold that mutex for their whole duration, so the records of two concurrent
-- writes never interleave and a write that fails midway cannot leave a half-sent prefix for the
-- next one: it closes the stream, as a cancelled `TcpStream` write does. A reader that finds
-- ciphertext queued (key update, alert, close_notify reply) sends it only when the mutex is
-- free; whoever holds the mutex sends until nothing is queued, so a skipped flush is never lost
-- and a reader never waits behind a writer that is blocked by back-pressure.
global <const> require, pcall, tostring, error, math, type

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local Stream = require("hecate.net.stream")
local BufferedReader = require("hecate.net.buffered_reader")
local BufferedWriter = require("hecate.net.buffered_writer")
local errors = require("hecate.net.errors")

--- The native sans-IO TLS session (rustls through mlua); see `packages/net/native`.
---@class hecate.net.TlsSession
---@field feed fun(self: hecate.net.TlsSession, data: string): integer
---@field feed_eof fun(self: hecate.net.TlsSession)
---@field drain fun(self: hecate.net.TlsSession): string
---@field read fun(self: hecate.net.TlsSession, max?: integer): string?, string?
---@field write fun(self: hecate.net.TlsSession, data: string, offset?: integer): integer  bytes taken from `offset` (0-based skip); 0 when nothing fits now
---@field is_handshaking fun(self: hecate.net.TlsSession): boolean
---@field wants_read fun(self: hecate.net.TlsSession): boolean
---@field wants_write fun(self: hecate.net.TlsSession): boolean
---@field send_close_notify fun(self: hecate.net.TlsSession)
---@field alpn fun(self: hecate.net.TlsSession): string?
---@field server_name fun(self: hecate.net.TlsSession): string?
---@field version fun(self: hecate.net.TlsSession): string?
---@field peer_certificate fun(self: hecate.net.TlsSession): string?
---@field close fun(self: hecate.net.TlsSession)  drops the connection state; idempotent

--- A TLS connection over an inner stream, which it owns.
---@class hecate.net.TlsStream: hecate.net.Stream
---@field private _session hecate.net.TlsSession
---@overload fun(inner: hecate.net.Stream, session: userdata): hecate.net.TlsStream
local TlsStream = core.class("TlsStream", nil, { implements = { Stream } })

--- Wraps `inner` and a native session. Prefer `net.connect_tls`, `net.tls.connect` and
--- `net.tls.accept`.
---@param inner hecate.net.Stream
---@param session userdata
---@private
function TlsStream:init(inner, session)
  self._inner = inner
  self._session = session --[[@as hecate.net.TlsSession]]
  self._pending = nil -- received ciphertext not yet accepted by the session
  self._closed = false
  self._shut = false -- `shutdown` ran: close_notify is queued or sent
  self._reading = false -- one reader at a time, as on `TcpStream`
  self._wrote = false -- the running `write` handed bytes to the session
  self._send = reactor.Mutex() -- the single sender of ciphertext (see the header)
end

--- Converts a native failure into a `TlsError`. The native module prefixes the kind of a failure
--- it can classify from the rustls error variant (`[untrusted_issuer] tls: ...`); that becomes
--- `context.reason` without parsing the message. mlua renders a Rust error as `runtime error: ...`
--- followed by a traceback: both are removed.
---@param message any
---@return hecate.net.TlsError
local function tls_error(message)
  local text = tostring(message):gsub("\nstack traceback:.*$", ""):gsub("^runtime error: ", "")
  local kind, rest = text:match("^%[(%l[%l_]*)%] (.*)$")
  if kind then return errors.tls_failure({ kind = kind, message = rest }) end
  return errors.tls_failure(text)
end

--- Calls a native session method, converting a failure into `TlsError`.
---@param session hecate.net.TlsSession
---@param method string
---@return any, any
local function call(session, method, ...)
  local ok, a, b = pcall(session[method], session, ...)
  if not ok then error(tls_error(a), 0) end
  return a, b
end

--- The error of a stream used after it was closed: the same `TransportError` (EBADF) as `TcpStream`.
---@param operation string
---@return hecate.core.NetworkError
local function closed_error(operation)
  return reactor.TransportError({
    message = "net.TlsStream." .. operation .. ": EBADF: the TLS stream is closed",
    context = { operation = operation, errno = "EBADF" },
  })
end

--- True for the error a cancelled computation receives (a deadline's expiry arrives as one,
--- before the scope turns it into `DeadlineExceededError`): it must never be swallowed.
---@param failure any
---@return boolean
local function is_cancellation(failure)
  return core.is_instance_of(failure, core.CancellationError)
end

--- Sends the ciphertext the session has queued, until none is left. The caller holds `_send`:
--- the inner write may suspend, and records must reach the wire in the order they were made.
---@async
---@return boolean sent  whether any ciphertext was written
---@private
function TlsStream:_pump()
  local sent = false
  while true do
    local out = call(self._session, "drain")
    if out == "" then return sent end
    self._inner:write(out)
    sent = true
  end
end

--- Takes the send mutex and sends what is queued (handshake flights).
---@async
---@return boolean sent
---@private
function TlsStream:_flush()
  local lock <close> = self._send:lock()
  return self:_pump()
end

--- Sends queued ciphertext (key updates, alerts, a close_notify reply) when there is some and no
--- other coroutine is sending; the sender in progress sends it otherwise. Never waits for a sender.
---@async
---@private
function TlsStream:_flush_queued()
  if not self._session:wants_write() then return end
  local lock <close> = self._send:try_lock()
  if lock == nil then return end
  self:_pump()
end

--- Runs `_flush_queued` where its failure must not mask another outcome (a transport that is
--- gone). Cancellation still propagates.
---@async
---@private
function TlsStream:_flush_best_effort()
  local ok, failure = pcall(self._flush_queued, self)
  if not ok and is_cancellation(failure) then error(failure, 0) end
end

--- Raises when the stream is closed.
---@param operation string
---@private
function TlsStream:_check(operation)
  if self:is_closed() then error(closed_error(operation), 0) end
end

--- Hands received ciphertext to the session; keeps what it did not accept for the next call.
--- On a protocol failure the queued alert is sent best-effort and the stream is closed, then
--- `TlsError` is raised (a cancellation that interrupts the alert is raised instead).
---@async
---@param data string
---@private
function TlsStream:_feed(data)
  while data ~= "" do
    local ok, consumed = pcall(self._session.feed, self._session, data)
    if not ok then
      local alerted, interruption = pcall(self._flush_queued, self)
      self:close()
      if not alerted and is_cancellation(interruption) then error(interruption, 0) end
      error(tls_error(consumed), 0)
    end
    if consumed == 0 then
      -- The session holds plaintext it wants read first.
      self._pending = data
      return
    end
    data = data:sub(consumed + 1)
  end
  self._pending = nil
end

--- Receives one chunk from the inner stream and feeds it (or the end of the transport).
---@async
---@private
function TlsStream:_receive()
  local pending = self._pending
  if pending then
    self:_feed(pending)
    if self._pending == pending then
      -- Nothing consumed and nothing readable: the session cannot make progress.
      self:close()
      error(errors.tls_failure("the TLS session made no progress", "stalled"), 0)
    end
    return
  end
  local chunk = self._inner:read()
  if chunk == nil then
    local ok, failure = pcall(self._session.feed_eof, self._session)
    if not ok then error(tls_error(failure), 0) end
    return "eof"
  end
  self:_feed(chunk)
end

--- Runs the handshake loop; `handshake` closes the stream when it fails.
---@async
---@private
function TlsStream:_handshake()
  while true do
    self:_flush()
    if not self._session:is_handshaking() then return end
    if self:_receive() == "eof" then
      error(errors.tls_failure("the transport ended during the TLS handshake", "transport_ended"), 0)
    end
  end
end

--- Runs the handshake to completion (RFC 8446 section 2): sends and receives flights until the
--- session is established. Raises `hecate.net.TlsError` when the peer fails verification
--- (certificate not trusted, name mismatch) or the transport ends first. On any failure,
--- cancellation (a deadline) included, the stream is closed.
---@async
function TlsStream:handshake()
  local ok, failure = pcall(self._handshake, self)
  if not ok then
    self:close()
    error(errors.qualify(failure, "net.TlsStream.handshake"), 0)
  end
end

--- Reads at most `max` decrypted bytes; nil after the peer's `close_notify` (clean end of stream).
--- Raises `TlsError` when the transport ends without `close_notify`, so truncation is never
--- taken for a clean end (RFC 8446 section 6.1). Cancelling a suspended read keeps the stream
--- open; the exception is a cancellation that interrupts the sending of ciphertext the session
--- queued (a key update or an alert), which closes the stream like any cancelled write. One
--- coroutine reads at a time. Raises `TransportError` (EBADF) on a closed stream.
---@async
---@param max? integer
---@return string?
function TlsStream:read(max)
  if max ~= nil and (math.type(max) ~= "integer" or max < 1) then
    error(core.ArgumentError(("net.TlsStream.read: expects a positive integer, got %s"):format(tostring(max))), 2)
  end
  self:_check("read")
  if self._reading then error(core.Error("net.TlsStream.read: another coroutine is already reading this stream"), 2) end
  self._reading = true
  local ok, result = pcall(self._read, self, max)
  self._reading = false
  if not ok then error(errors.qualify(result, "net.TlsStream.read"), 0) end
  return result
end

--- The loop of `read`.
---@async
---@param max? integer
---@return string?
---@private
function TlsStream:_read(max)
  while true do
    local data, state = call(self._session, "read", max)
    if data ~= nil then return data end
    if state == "closed" then
      self:_flush_best_effort() -- our close_notify reply
      return nil
    end
    if state == "eof" then
      error(errors.tls_failure("the transport ended without a TLS close_notify (truncated stream)", "truncated"), 0)
    end
    self:_flush_queued() -- only when something is queued and nobody is sending
    if self:_receive() == "eof" then self:_flush_best_effort() end
  end
end

--- Encrypts and writes all of `data`, or raises; suspends under back-pressure. One write at a
--- time: concurrent writes run one after the other, each intact. A write that fails after the
--- session accepted bytes (a cancellation included) closes the stream and the inner stream, since
--- the bytes sent are unknown; one cancelled while waiting its turn changes nothing. Raises
--- `TransportError` (EBADF) on a closed stream and (EPIPE) after `shutdown`.
---@async
---@param data string
function TlsStream:write(data)
  self:_check("write")
  local lock <close> = self._send:lock()
  self:_check("write") -- closed while waiting for the turn
  if self._shut then
    error(reactor.TransportError({
      message = "net.TlsStream.write: EPIPE: the TLS stream was shut down",
      context = { operation = "write", errno = "EPIPE" },
    }), 0)
  end
  self._wrote = false
  local ok, failure = pcall(self._write, self, data)
  if not ok then
    if self._wrote then self:close() end
    error(errors.qualify(failure, "net.TlsStream.write"), 0)
  end
end

--- The loop of `write`; the caller holds `_send`.
---@async
---@param data string
---@private
function TlsStream:_write(data)
  local total, offset = #data, 0
  while offset < total do
    -- The session bounds its send buffer: take what fits, send it, repeat (back-pressure). The
    -- offset spares a copy of the rest of `data` per pass.
    local accepted = call(self._session, "write", data, offset)
    if accepted > 0 then
      self._wrote = true
      offset = offset + accepted
    end
    if not self:_pump() and accepted == 0 then
      error(errors.tls_failure("the TLS session accepts no more data (closed or stalled)", "stalled"), 0)
    end
  end
end

--- Sends `close_notify` and half-closes the transport (the stream stays readable). Flush any
--- `BufferedWriter` first (RFC 8446 section 6.1). Idempotent. A shutdown that fails or is
--- cancelled midway closes the stream. Waits for a write in progress.
---@async
function TlsStream:shutdown()
  self:_check("shutdown")
  local lock <close> = self._send:lock()
  self:_check("shutdown")
  if self._shut then return end
  self._shut = true
  local ok, failure = pcall(self._shutdown_locked, self)
  if not ok then
    self:close()
    error(errors.qualify(failure, "net.TlsStream.shutdown"), 0)
  end
end

--- The body of `shutdown`; the caller holds `_send`.
---@async
---@private
function TlsStream:_shutdown_locked()
  call(self._session, "send_close_notify")
  self:_pump()
  local inner = self._inner --[[@as table]]
  if inner.shutdown then inner:shutdown() end
end

--- Closes the inner stream and drops the session state. Idempotent, never suspends. It cannot
--- send `close_notify` (that needs a write): call `shutdown` first for an orderly end.
function TlsStream:close()
  self._closed = true
  self._inner:close()
  self._session:close()
end

--- Closes at the end of a `<close>` scope, including on cancellation.
function TlsStream:__close() self:close() end

--- True once closed, or when the inner stream was closed under it (a cancelled write).
---@return boolean
function TlsStream:is_closed()
  if self._closed then return true end
  local inner = self._inner --[[@as table]]
  return type(inner.is_closed) == "function" and inner:is_closed()
end

--- The negotiated application protocol (ALPN, RFC 7301), or nil.
---@return string?
function TlsStream:alpn() return self._session:alpn() end

--- The server name (SNI, RFC 6066 section 3) the client sent, on a stream accepted by a
--- server; nil on a client stream, whose own server name is the argument it connected with.
---@return string?
function TlsStream:requested_server_name() return self._session:server_name() end

--- The protocol version, `"TLSv1.3"` or `"TLSv1.2"`.
---@return string?
function TlsStream:version() return self._session:version() end

--- DER of the peer's end-entity certificate, once verified.
---@return string?
function TlsStream:peer_certificate() return self._session:peer_certificate() end

--- The peer's address, from the inner stream (the stream must have one, as `TcpStream` does).
---@return hecate.reactor.SocketAddress
function TlsStream:peer_address()
  local inner = self._inner --[[@as table]]
  if type(inner.peer_address) ~= "function" then error(core.Error("net.TlsStream.peer_address: the inner stream has no peer address"), 2) end
  return inner:peer_address()
end

--- The local address, from the inner stream (the stream must have one, as `TcpStream` does).
---@return hecate.reactor.SocketAddress
function TlsStream:local_address()
  local inner = self._inner --[[@as table]]
  if type(inner.local_address) ~= "function" then error(core.Error("net.TlsStream.local_address: the inner stream has no local address"), 2) end
  return inner:local_address()
end

--- Enables or disables Nagle's algorithm on the inner stream (the stream must support it, as
--- `TcpStream` does).
---@param enabled boolean
function TlsStream:set_nodelay(enabled)
  local inner = self._inner --[[@as table]]
  if type(inner.set_nodelay) ~= "function" then error(core.Error("net.TlsStream.set_nodelay: the inner stream has no set_nodelay"), 2) end
  inner:set_nodelay(enabled)
end

--- A `BufferedReader` over this stream (which it does not own).
---@param options? { limit?: integer }
---@return hecate.net.BufferedReader
function TlsStream:reader(options) return BufferedReader(self, options) end

--- A `BufferedWriter` over this stream (which it does not own); flush it before `shutdown`.
---@param options? { capacity?: integer }
---@return hecate.net.BufferedWriter
function TlsStream:writer(options) return BufferedWriter(self, options) end

core.finalise(TlsStream)

return TlsStream
