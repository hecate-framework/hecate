-- The connection handling of `hecate.http.Server`: reading parser events with the deadline of the connection's state,
-- the content reader of a request, the checks made on a head, and the loops that serve one request and one connection
-- (including the TLS handshake of an accepted connection).
-- Internal to `hecate.http`: not public API. Only `server.lua` requires it.
-- Every function takes the server (`self`) first: it reads the settings of the server and its connection registry.
global <const> require, type, error, pcall, ipairs, math, string, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local Parser = require("hecate.http.parser")
local Request = require("hecate.http.request")
local ContentStream = require("hecate.http.content")
local problem = require("hecate.http.problem")
local HandshakeStream = require("hecate.http.handshake_stream")
local responses = require("hecate.http.internal.server_response")

local ContentError = ContentStream.ContentError
local send, flush = responses.send, responses.flush
local send_response, send_problem = responses.send_response, responses.send_problem
local serve_action = require("hecate.http.serve_request")

---@class hecate.http.internal.server_connection
local M = {}

-- Bytes read from a connection at once: never more than the parser's read buffer (llhttp's `feed` returns every
--- event of the chunk in one list).
local READ_SIZE <const> = 16384

--- Seconds a fresh connection (no byte of its first request head yet) is given at shutdown to send its request, before it
--- is closed. Not a server option: a connection handed over just before the stop needs only a moment, and a silent one
--- must not hold the shutdown (`head_timeout` defaults to 60 s, too long for that).
M.FRESH_GRACE = 1

---@return boolean
local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end

local function is_deadline(err) return core.is_instance_of(err, core.DeadlineExceededError) end

-- Reading ---------------------------------------------------------------------------------------------------------

--- Reads one chunk with the deadline that fits the state of the connection: between reads while content is read (and
--- by the total deadline of the content, when set); until the end of the head while one is pending (a whole-head
--- deadline: bytes that keep arriving do not extend it); the idle timeout otherwise.
---@async
local function read_chunk(self, conn)
  local limit
  if conn.in_content then
    limit = self._content_timeout
    if conn.request_timeout ~= nil then limit = math.min(limit, math.max(0, conn.request_timeout - reactor.now())) end
  elseif conn.head_deadline ~= nil then
    limit = math.max(0, conn.head_deadline - reactor.now())
  else
    limit = self._idle_timeout
  end
  local stream = conn.stream
  return reactor.deadline(limit, stream.read, stream, READ_SIZE)
end

--- The next parser event of the connection, or nil and a reason: a `ParseError`, or the string "eof" when the peer
--- closed. Events that completed before a failure are delivered first.
---@async
local function next_event(self, conn)
  while true do
    local queue, position = conn.queue, conn.position
    local event = queue[position]
    if event ~= nil then
      queue[position] = nil
      conn.position = position + 1
      return event
    end
    if conn.failure ~= nil then return nil, conn.failure end
    if conn.eof then return nil, "eof" end
    local chunk = read_chunk(self, conn)
    local events, err
    if chunk == nil then
      conn.eof = true
      events, err = conn.parser:finish()
    else
      events, err = conn.parser:feed(chunk)
    end
    for _, parsed in ipairs(events) do
      conn.tail = conn.tail + 1
      queue[conn.tail] = parsed
    end
    if err ~= nil and chunk ~= nil then conn.failure = err end
    -- The first byte of a head has arrived: its deadline starts now (a head that follows a pipelined request is timed
    -- when the connection turns to it, see `serve_connection`).
    -- Bytes that began no message (bare CRLF before a head, which llhttp skips) count as a pending head as well: a chunk that
    -- produced no event and left no message open still absorbed bytes.
    conn.partial = conn.parser:in_message() or (chunk ~= nil and #events == 0)
    if conn.partial then conn.fresh = false end -- the first byte of the first request head arrived
    if conn.waiting and conn.partial and conn.head_deadline == nil then conn.head_deadline = reactor.now() + self._head_timeout end
  end
end

--- The reader of the content of one request: it sends `100 Continue` before its first read when the client asked for
--- it (RFC 9110, section 10.1.1), and ends at the parser's `complete` event.
---@param head hecate.http.parser.Head
---@param expecting boolean
---@return hecate.http.ContentStream
local function open_content(self, conn, head, expecting)
  local continued, done = false, false
  local function fail(status, reason, message)
    conn.broken = true
    error(ContentError({ message = message, context = { status = status, reason = reason } }), 0)
  end
  local function pull()
    if done then return nil end
    if expecting and not continued then
      continued = true
      send(self, conn, "HTTP/1.1 100 Continue\r\n\r\n")
      flush(self, conn)
    end
    conn.in_content = true
    local ok, event, err = pcall(next_event, self, conn)
    if not ok then
      conn.broken = true
      if is_deadline(event) then fail(408, "timeout", "http.Server: the request content stalled") end
      error(event, 0)
    end
    if event == nil then
      conn.broken = true
      if err == "eof" then fail(400, "truncated", "http.Server: the connection ended inside the request content") end
      error(err, 0)
    end
    if event.type == "data" then return event.data end
    if event.type == "complete" then
      done, conn.in_content = true, false
      return nil
    end
    fail(400, "malformed", "http.Server: unexpected event in the request content")
  end
  return ContentStream(pull, { limit = self._max_content })
end

--- Whether `value` is `uri-host [ ":" port ]` (RFC 3986 sections 3.2.2 and 3.2.3), conservatively: a registered name of
--- unreserved characters and percent sequences, an IPv4 address, or an IPv6 literal in brackets; a port of at most five digits.
---@param value string
---@return boolean
local function valid_host(value)
  local host, rest
  if string.sub(value, 1, 1) == "[" then
    host, rest = string.match(value, "^(%[[%x:%.]+%])(.*)$")
  else
    host, rest = string.match(value, "^([%w%-%._~%%]+)(.*)$")
  end
  if host == nil then return false end
  return rest == "" or string.find(rest, "^:%d?%d?%d?%d?%d?$") ~= nil
end

--- The status and detail to answer a head with before any action runs, or nil when the request may be handled.
---@param head hecate.http.parser.Head
---@return integer? status
---@return string? detail
local function refuse(self, head)
  -- RFC 9112, section 3.2: a server MUST answer 400 to an HTTP/1.1 request without exactly one Host field.
  local hosts = head.fields:get_all("Host")
  if head.version == "HTTP/1.1" and #hosts ~= 1 then
    return 400, "The request needs exactly one Host field."
  end
  -- The field is `uri-host [ ":" port ]` and nothing else: no list, path, userinfo or blank (RFC 9112 section 3.2).
  if #hosts == 1 and not valid_host(hosts[1]) then
    return 400, "The Host field is not a host and an optional port."
  end
  -- An absolute-form target (RFC 9112 section 3.2.2) is accepted only when its authority is the Host: a server that
  -- routed on one and a proxy on the other would disagree about the request.
  if string.find(head.target, "^%a[%w+.-]*://") then
    local scheme, authority = string.match(head.target, "^(%a[%w+.-]*)://([^/?#]*)")
    local lower = string.lower(scheme)
    if (lower ~= "http" and lower ~= "https") or string.find(authority, "@", 1, true) or string.find(head.target, "#", 1, true)
      or hosts[1] == nil or string.lower(authority) ~= string.lower(hosts[1]) then
      return 400, "The request target does not match its Host field."
    end
  end
  if head.upgrade then
    return 501, "The server does not switch protocols."
  end
  local expect = head.fields:combined("Expect")
  if expect ~= nil and head.version == "HTTP/1.1" and string.lower((string.match(expect, "^[ \t]*(.-)[ \t]*$"))) ~= "100-continue" then
    return 417, "The expectation of the request cannot be met."
  end
  if head.content_length ~= nil and head.content_length > self._max_content then
    return 413, nil
  end
  return nil
end

--- Serves one request from its head: one scope, one computation running the action. Returns whether the connection
--- stays open.
---@async
---@param head hecate.http.parser.Head
---@return boolean keep_alive
local function serve_request(self, conn, head)
  local info = { method = head.method, target = head.target, version = head.version, keep_alive = head.keep_alive }
  local status, detail = refuse(self, head)
  if status ~= nil then
    send_problem(self, conn, info, status, detail)
    return false
  end
  local expecting = head.version == "HTTP/1.1" and (head.chunked or (head.content_length or 0) > 0)
    and head.fields:has("Expect")
  local reader = open_content(self, conn, head, expecting)
  local made, request = pcall(Request, {
    method = head.method, target = head.target, fields = head.fields, version = head.version,
    peer_address = conn.peer, content_stream = reader,
  })
  if not made then
    send_problem(self, conn, info, 400, nil)
    return false
  end
  if string.find(head.target, "^%a[%w+.-]*://") then
    -- absolute-form (accepted only for the Host): the path and query are those of the target after the authority
    local rest = string.match(head.target, "^%a[%w+.-]*://[^/?#]*(.*)$")
    local path, query = string.match(rest, "^([^?]*)%??(.*)$")
    request.path = path == "" and "/" or path
    request.query = string.find(rest, "?", 1, true) and query or nil
  end
  return reactor.scope(function(scope)
    request.scope = scope
    local response, failure = scope:fork(serve_action, self._action, request):value()
    if failure ~= nil then
      self:_log("error", "http.Server: the action failed", { method = head.method, path = request.path, error = tostring(failure) })
      self:_report("the action failed", failure)
    end
    -- A client that expects 100 Continue may still send the content the action never asked for: close (RFC 9110, 10.1.1).
    local abandoned = expecting and not reader:is_started()
    local keep = send_response(self, conn, info, response, abandoned)
    if not keep or conn.broken or abandoned then return false end
    -- The action left content unread: drain it (bounded by the content limit) so the next request can be parsed.
    local drained = pcall(reactor.deadline, self._drain_timeout, function()
      while not reader:is_finished() do reader:read() end
    end)
    return drained and not conn.broken
  end)
end

--- Serves the requests of one connection in order until it ends.
---@async
local function serve_connection(self, conn)
  while true do
    conn.waiting, conn.in_content = true, false
    -- Bytes of the next head already read (pipelining) start its deadline now: it is held to `head_timeout`, not to
    -- `idle_timeout`.
    conn.head_deadline = conn.partial and (reactor.now() + self._head_timeout) or nil
    local ok, event, failure = pcall(next_event, self, conn)
    conn.waiting = false
    if not ok then
      if is_deadline(event) and conn.head_deadline ~= nil then
        send_problem(self, conn, { version = "HTTP/1.1", keep_alive = false }, 408, nil)
      end
      return
    end
    if event == nil then
      if failure ~= "eof" then
        local status, detail = problem.of_error(failure)
        send_problem(self, conn, { version = "HTTP/1.1", keep_alive = false }, status, detail)
      end
      return
    end
    conn.fresh = false
    if event.type ~= "head" then return end
    conn.head_deadline = nil
    conn.request_timeout = reactor.now() + self._request_timeout
    local keep = serve_request(self, conn, event)
    if not keep or self._stopping then return end
  end
end

--- Runs the TLS handshake of an accepted connection under its deadline and byte budget. Returns the TLS stream, or nil
--- when the connection was dropped (the stream is closed). Nothing about the failure reaches the client; the log
--- receives the class of the failure and the peer address.
---@async
---@param raw hecate.net.TcpStream
---@return hecate.net.TlsStream?
local function handshake(self, raw)
  local known, peer = pcall(raw.peer_address, raw)
  local limited = HandshakeStream(raw, self._max_handshake_bytes)
  self._handshaking[limited] = true
  local ok, result = pcall(net.tls.accept, limited, self._tls, { handshake_timeout = self._handshake_timeout })
  self._handshaking[limited] = nil
  if ok then
    limited:release()
    return result
  end
  limited:close()
  if not is_cancellation(result) and not self._stopping then
    local failure = result --[[@as table]]
    local reason = core.is_instance_of(failure, core.Error) and ((failure.context and failure.context.reason) or failure.code) or "error"
    self:_log("warning", "http.Server: TLS handshake failed", {
      peer = known and (tostring(peer.ip) .. ":" .. tostring(peer.port)) or "unknown",
      reason = tostring(reason),
    })
  end
  return nil
end

--- The grace of a fresh connection at shutdown: it is closed when no byte of a request head arrived within
--- `FRESH_GRACE` seconds (or what is left of the grace period of `shutdown`, when shorter). Runs as a task of the server's
--- scope and is cancelled when the connection ends, so it never holds `shutdown` longer than the connection lives.
---@async
local function watch_fresh(self, conn)
  reactor.sleep(math.min(M.FRESH_GRACE, self._stop_grace or M.FRESH_GRACE))
  if conn.fresh and self._connections[conn] then conn.stream:close() end
end

--- Starts the grace of `conn` when it is fresh and the server is stopping. Called by `shutdown` for the connections it
--- finds, and by `run_connection` for a connection accepted just before the accept loop stopped.
function M.grace_fresh(self, conn)
  if not conn.fresh or conn.watcher ~= nil or self._scope == nil then return end
  local ok, task = pcall(self._scope.fork, self._scope, watch_fresh, self, conn)
  if ok then conn.watcher = task end
end

---@async
local function run_connection(self, raw)
  local stream = raw
  if self._tls ~= nil then
    local secured = handshake(self, raw)
    self._handshakes:release()
    if secured == nil then
      if self._slots ~= nil then self._slots:release() end
      return
    end
    stream = secured
  end
  local conn = {
    stream = stream, writer = stream:writer(), parser = Parser.request(self._limits), queue = {}, position = 1, tail = 0,
    waiting = false, fresh = true, partial = false, in_content = false, broken = false, eof = false,
  }
  local known, peer = pcall(stream.peer_address, stream)
  conn.peer = known and peer or nil
  self._connections[conn] = true
  if self._stopping then M.grace_fresh(self, conn) end
  local ok, err = pcall(serve_connection, self, conn)
  self._connections[conn] = nil
  if conn.watcher ~= nil then conn.watcher:cancel() end
  conn.parser:close()
  if ok and not stream:is_closed() then
    -- Half-close first, so that the last bytes are not lost to a reset when the client still sends (TLS: close_notify).
    pcall(reactor.deadline, 1, stream.shutdown, stream)
  end
  stream:close()
  if self._slots ~= nil then self._slots:release() end
  if not ok and not is_cancellation(err) and not self._stopping then
    self:_report("a connection ended with a failure", err)
  end
end

M.run_connection = run_connection

return M
