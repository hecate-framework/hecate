-- TlsStream: a `Stream` that encrypts over another `Stream` (ADR 0021). The native session is
-- sans-IO (`rustls`): this class moves bytes between it and the inner stream, so every
-- suspension happens in the inner stream and the reactor stays in charge of I/O.
global <const> require, pcall, tostring, error, math, type

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local Stream = require("hecate.net.stream")
local BufferedReader = require("hecate.net.buffered_reader")
local BufferedWriter = require("hecate.net.buffered_writer")
local TlsError = require("hecate.net.errors").TlsError

--- The native sans-IO TLS session (rustls through mlua); see `packages/net/native`.
---@class hecate.net.TlsSession
---@field feed fun(self: hecate.net.TlsSession, data: string): integer
---@field feed_eof fun(self: hecate.net.TlsSession)
---@field drain fun(self: hecate.net.TlsSession): string
---@field read fun(self: hecate.net.TlsSession, max?: integer): string?, string?
---@field write fun(self: hecate.net.TlsSession, data: string): integer
---@field is_handshaking fun(self: hecate.net.TlsSession): boolean
---@field wants_read fun(self: hecate.net.TlsSession): boolean
---@field wants_write fun(self: hecate.net.TlsSession): boolean
---@field send_close_notify fun(self: hecate.net.TlsSession)
---@field alpn fun(self: hecate.net.TlsSession): string?
---@field server_name fun(self: hecate.net.TlsSession): string?
---@field version fun(self: hecate.net.TlsSession): string?
---@field peer_certificate fun(self: hecate.net.TlsSession): string?

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
  self._send = reactor.Mutex() -- keeps drained ciphertext in order on the inner stream
end

--- Converts a native failure into a `TlsError`.
---@param message any
---@return hecate.net.TlsError
local function tls_error(message)
  local text = tostring(message):gsub("\nstack traceback:.*$", "")
  return TlsError(text)
end

--- Sends the ciphertext the session has queued (handshake flights, alerts, records). Draining
--- and writing happen under a mutex: the inner write may suspend, and a concurrent reader
--- (alerts, key updates) and writer must not reorder TLS records on the wire.
---@async
---@return boolean sent  whether any ciphertext was written
---@private
function TlsStream:_flush()
  local lock <close> = self._send:lock()
  local out = self._session:drain()
  if out == "" then return false end
  self._inner:write(out)
  return true
end

--- Raises when the stream is closed.
---@private
function TlsStream:_check()
  if self:is_closed() then error(core.Error("the TLS stream is closed"), 0) end
end

--- Hands received ciphertext to the session; keeps what it did not accept for the next call.
--- On a protocol failure the queued alert is sent best-effort, then `TlsError` is raised.
---@async
---@param data string
---@private
function TlsStream:_feed(data)
  while data ~= "" do
    local ok, consumed = pcall(self._session.feed, self._session, data)
    if not ok then
      pcall(self._flush, self)
      self._inner:close()
      self._closed = true
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
      self._inner:close()
      self._closed = true
      error(TlsError("the TLS session made no progress"), 0)
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

--- Runs the handshake to completion (RFC 8446 section 2): sends and receives flights until the
--- session is established. Raises `hecate.net.TlsError` when the peer fails verification
--- (certificate not trusted, name mismatch) or the transport ends first.
---@async
function TlsStream:handshake()
  while true do
    self:_flush()
    if not self._session:is_handshaking() then return end
    if self:_receive() == "eof" then
      self._inner:close()
      self._closed = true
      error(TlsError("the transport ended during the TLS handshake"), 0)
    end
  end
end

--- Reads at most `max` decrypted bytes; nil after the peer's `close_notify` (clean end of stream).
--- Raises `TlsError` when the transport ends without `close_notify`, so truncation is never
--- taken for a clean end (RFC 8446 section 6.1). Cancelling keeps the stream open.
---@async
---@param max? integer
---@return string?
function TlsStream:read(max)
  if max ~= nil and (math.type(max) ~= "integer" or max < 1) then
    error(core.ArgumentError("TlsStream:read expects a positive integer"), 2)
  end
  self:_check()
  while true do
    local data, state = self._session:read(max)
    if data ~= nil then return data end
    if state == "closed" then
      pcall(self._flush, self)
      return nil
    end
    if state == "eof" then
      error(TlsError("the transport ended without a TLS close_notify (truncated stream)"), 0)
    end
    self:_flush() -- key updates, alerts or tickets the session queued
    if self:_receive() == "eof" and self._session:wants_write() then self:_flush() end
  end
end

--- Encrypts and writes all of `data`, or raises; suspends under back-pressure. A write
--- cancelled midway closes the inner stream (the bytes sent are unknown).
---@async
---@param data string
function TlsStream:write(data)
  self:_check()
  while data ~= "" do
    -- The session bounds its send buffer: take what fits, send it, repeat (back-pressure).
    local accepted = self._session:write(data)
    data = data:sub(accepted + 1)
    if not self:_flush() and accepted == 0 then
      error(TlsError("the TLS session accepts no more data (closed or stalled)"), 0)
    end
  end
end

--- Sends `close_notify` and half-closes the transport (the stream stays readable). Flush any
--- `BufferedWriter` first (RFC 8446 section 6.1).
---@async
function TlsStream:shutdown()
  self:_check()
  self._session:send_close_notify()
  self:_flush()
  local inner = self._inner --[[@as table]]
  if inner.shutdown then inner:shutdown() end
end

--- Closes the inner stream. Idempotent, never suspends. It cannot send `close_notify` (that
--- needs a write): call `shutdown` first for an orderly end.
function TlsStream:close()
  self._closed = true
  self._inner:close()
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

--- The server name a client sent (SNI), on a server stream; nil on a client stream.
---@return string?
function TlsStream:server_name() return self._session:server_name() end

--- The protocol version, `"TLSv1.3"` or `"TLSv1.2"`.
---@return string?
function TlsStream:version() return self._session:version() end

--- DER of the peer's end-entity certificate, once verified.
---@return string?
function TlsStream:peer_certificate() return self._session:peer_certificate() end

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
