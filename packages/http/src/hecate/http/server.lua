-- The HTTP/1.1 server over hecate.net streams (RFC 9110, RFC 9112; ADR 0003; ADR 0019).
--
-- Shape: `serve` accepts connections in a scope; each connection is one computation of that scope, and each request
-- one scope of its own with one computation running the action (concurrency.md, "Structured concurrency"). A
-- connection serves its requests one after the other, so the responses of pipelined requests come in request order
-- (RFC 9112, section 9.3.2). The parser is fed chunks of at most READ_SIZE bytes and closed when the connection ends.
global <const> require, type, error, pcall, pairs, ipairs, math, string, tostring, os

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local json = require("hecate.json")
local Parser = require("hecate.http.parser")
local Request = require("hecate.http.request")
local Response = require("hecate.http.response")
local ContentStream = require("hecate.http.content")
local problem = require("hecate.http.problem")
local wire = require("hecate.http.wire")
local Status = require("hecate.http.status")
local Fields = require("hecate.http.fields")
local HandshakeStream = require("hecate.http.handshake_stream")

local ContentError = ContentStream.ContentError

--- Bytes read from a connection at once: never more than the parser's read buffer (llhttp's `feed` returns every
--- event of the chunk in one list).
local READ_SIZE <const> = 16384

--- Options of the server. Every limit has a safe default; a server never runs unbounded.
---@class hecate.http.ServerOptions
---@field host? string  a NUMERIC address, IPv4 or IPv6, for `listen` (default "127.0.0.1": the loopback interface only); a name is refused
---@field port? integer  0 to 65535 for `listen`; 0 picks a free port (default 8080)
---@field backlog? integer  pending connections the kernel queues (default 128)
---@field max_connections? integer  connections served at once (default: no limit; an integer limits, and the others wait in the backlog)
---@field max_content? integer  bytes of request content (default 1048576; over it: 413)
---@field head_timeout? number  seconds to receive a request head once its first byte arrived (default 60; counted from the first byte of the head to its end, not between reads; then 408)
---@field idle_timeout? number  seconds a connection may wait for the next request (default 75; then closed silently)
---@field content_timeout? number  seconds between two reads of request content (default 60; a timeout between two reads, not a limit on the whole content; then 408)
---@field request_timeout? number  seconds from the end of a head to the last byte of its content (default 300; then 408); `content_timeout` still applies between reads
---@field drain_timeout? number  seconds to drain content the action left unread after the response (default 5; then the connection closes)
---@field write_timeout? number  seconds a write to the client may take (default 60; then the connection is closed)
---@field parser? hecate.http.parser.Options  limits of the message parser (target, field, head size, field count)
---@field tls? hecate.net.TlsServerOptions|hecate.net.TlsServerConfig  serve HTTPS: the options of `net.tls.server_config` (ALPN defaults to `http/1.1`), or a configuration built by it
---@field handshake_timeout? number  seconds a TLS handshake may take (default 10; the connection is dropped); needs `tls`
---@field max_handshakes? integer  TLS handshakes in progress at once (default 64); the other connections wait in the backlog; needs `tls`
---@field max_handshake_bytes? integer  bytes read from a client during its handshake (default 65536; over it the connection is dropped); needs `tls`
---@field logger? hecate.log.Logger  receives the failed handshakes, with the peer address (default: none)
---@field on_error? fun(err: any)  called with the failure of a action or a connection (the client only sees generic problem details)

--- Defaults of the settings, exported so that documentation and tests read one source.
--- The defaults of the server's settings. Settings without an entry have no default value: `max_connections` (no limit; the
--- process descriptor limit and the timeouts bound it), `tls` (plain HTTP), `parser` (the parser's own limits), `logger`
--- and `on_error` (none).
---@class hecate.http.ServerDefaults
---@field host string
---@field port integer
---@field backlog integer
---@field max_content integer
---@field head_timeout number
---@field idle_timeout number
---@field content_timeout number
---@field write_timeout number
---@field request_timeout number
---@field drain_timeout number
---@field handshake_timeout number
---@field max_handshakes integer
---@field max_handshake_bytes integer

---@type hecate.http.ServerDefaults
local DEFAULTS <const> = {
  host = "127.0.0.1",
  port = 8080,
  backlog = 128,
  -- max_connections: absent, no limit (the file-descriptor limit of the process and the timeouts bound the resource)
  max_content = 1048576,
  head_timeout = 60,
  idle_timeout = 75,
  content_timeout = 60,
  write_timeout = 60,
  request_timeout = 300,
  drain_timeout = 5,
  handshake_timeout = 10,
  max_handshakes = 64,
  max_handshake_bytes = 65536,
}

--- An HTTP/1.1 server: `serve` accepts connections from a listener and answers each request with the action.
---@class hecate.http.Server
---@field DEFAULTS hecate.http.ServerDefaults  the defaults of the settings
---@overload fun(action: (fun(request: hecate.http.Request): hecate.http.Response), options?: hecate.http.ServerOptions): hecate.http.Server
local Server = core.class("Server")
Server.DEFAULTS = DEFAULTS

local KNOWN <const> = {
  host = true, port = true, backlog = true, max_connections = true, max_content = true, head_timeout = true,
  idle_timeout = true, content_timeout = true, request_timeout = true, drain_timeout = true, write_timeout = true, parser = true, on_error = true,
  tls = true, handshake_timeout = true, max_handshakes = true, max_handshake_bytes = true, logger = true,
}

---@param host string
---@return boolean
local function is_numeric_address(host)
  local a, b, c, d = string.match(host, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if a then
    for _, octet in ipairs({ a, b, c, d }) do
      if #octet > 3 or math.tointeger(octet) > 255 then return false end
    end
    return true
  end
  return string.find(host, ":", 1, true) ~= nil and string.find(host, "^[%x:%.]+$") ~= nil
end

local function bad(name, expected, value)
  error(core.ArgumentError(("http.Server: invalid %s: expected %s"):format(name, expected)), 4)
end

--- Creates a server; nothing is bound until `listen` or `serve`.
---
--- Raises `hecate.core.ArgumentError` for a action that is not a function, an unknown or invalid option, or a host
--- that is not a numeric address (a name would bind every address the resolver lists, networking.md "TCP").
---@param action fun(request: hecate.http.Request): hecate.http.Response  runs in its own scope, once per request
---@param options? hecate.http.ServerOptions
function Server:init(action, options)
  if type(action) ~= "function" then error(core.ArgumentError("http.Server: the action must be a function"), 3) end
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Server: options must be a table"), 3) end
  for key in pairs(options) do
    if not KNOWN[key] then error(core.ArgumentError(("http.Server: unknown option %s"):format(tostring(key))), 3) end
  end
  local host = options.host
  if host == nil then host = DEFAULTS.host end
  if type(host) ~= "string" or not is_numeric_address(host) then
    bad("host", "a numeric IPv4 or IPv6 address (a name binds every address it resolves to; use \"0.0.0.0\" or \"::\" to serve every interface)", host)
  end
  ---@return integer
  local function integer(name, minimum, maximum)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as integer]] end
    if math.type(value) ~= "integer" or value < minimum or value > maximum then
      bad(name, ("an integer from %d to %d"):format(minimum, maximum), value)
    end
    return value
  end
  ---@return number
  local function seconds(name)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as number]] end
    if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
      bad(name, "a positive finite number of seconds", value)
    end
    return value
  end
  if options.on_error ~= nil and type(options.on_error) ~= "function" then bad("on_error", "a function", options.on_error) end
  if options.tls == nil then
    for _, name in ipairs({ "handshake_timeout", "max_handshakes", "max_handshake_bytes" }) do
      if options[name] ~= nil then bad(name, "unset: it applies to TLS only, and no `tls` option was given", options[name]) end
    end
  end
  if options.logger ~= nil and (type(options.logger) ~= "table" or type(options.logger.log) ~= "function") then
    bad("logger", "a hecate.log.Logger", options.logger)
  end
  self._action = action
  self._host = host
  self._port = integer("port", 0, 65535)
  self._backlog = integer("backlog", 1, 65535)
  self._max_connections = options.max_connections ~= nil and integer("max_connections", 1, 1000000) or nil
  self._max_content = integer("max_content", 0, 1099511627776)
  self._head_timeout = seconds("head_timeout")
  self._idle_timeout = seconds("idle_timeout")
  self._content_timeout = seconds("content_timeout")
  self._write_timeout = seconds("write_timeout")
  self._request_timeout = seconds("request_timeout")
  self._drain_timeout = seconds("drain_timeout")
  self._handshake_timeout = seconds("handshake_timeout")
  self._max_handshakes = integer("max_handshakes", 1, 1000000)
  self._max_handshake_bytes = integer("max_handshake_bytes", 1, 16777216)
  self._logger = options.logger
  local tls = options.tls
  if type(tls) == "table" then
    local config = {}
    for key, value in pairs(tls) do config[key] = value end
    if config.alpn == nil then config.alpn = { "http/1.1" } end
    tls = net.tls.server_config(config)
  elseif tls ~= nil and type(tls) ~= "userdata" then
    bad("tls", "a table of net.tls.server_config options or a configuration it built", tls)
  end
  self._tls = tls
  self._handshaking = {}
  self._handshakes = reactor.Semaphore(self._max_handshakes)
  if options.parser ~= nil then Parser.request(options.parser):close() end -- validates the limits now
  self._limits = options.parser
  self._on_error = options.on_error
  self._listener = nil
  self._connections = {}
  self._stopping = false
  self._forced = false
  self._scope = nil
  self._accepting = nil
  self._serving = false
  self._slots = self._max_connections ~= nil and reactor.Semaphore(self._max_connections) or nil -- nil: no limit
  self._finished = reactor.Semaphore(0)
end

--- Reports a failure to `on_error` (an error of that function is discarded).
---@param message string
---@param err any
function Server:_report(message, err)
  local report = self._on_error
  if report ~= nil then
    pcall(report, core.is_instance_of(err, core.Error) and err or core.Error({ message = message .. ": " .. tostring(err) }))
  end
end

--- The address the server listens on, `{ ip, port, family }`, or nil when it is not serving.
---@return hecate.reactor.SocketAddress?
function Server:local_address()
  return self._listener and self._listener:local_address() or nil
end

--- Whether `shutdown` was called (public: a kernel can refuse new work while the server drains). There is no `Server:close()`:
--- stopping suspends (it waits for the requests in flight), so the only stop is `shutdown`, which a `<close>` scope cannot do.
---@return boolean
function Server:is_stopping() return self._stopping end

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
    if conn.waiting and conn.partial and conn.head_deadline == nil then conn.head_deadline = reactor.now() + self._head_timeout end
  end
end

-- Writing ---------------------------------------------------------------------------------------------------------

---@async
local function send(self, conn, data)
  if data == "" then return end
  reactor.deadline(self._write_timeout, conn.writer.write, conn.writer, data)
end

---@async
local function flush(self, conn)
  reactor.deadline(self._write_timeout, conn.writer.flush, conn.writer)
end

---@type integer, string
local last_date_time, last_date = 0, ""
local function date_now()
  local now = os.time()
  if now ~= last_date_time then last_date_time, last_date = now, wire.http_date(now) end
  return last_date
end

local HOP_BY_HOP <const> = { "Connection", "Keep-Alive", "Proxy-Connection", "Transfer-Encoding", "Content-Length" }


--- The response a action produced, or the problem details for what went wrong. A action must return a `Response`
--- with a final status (200 to 599) and content that is nil, a string, a table (serialised as JSON) or a function.
---@param ok boolean
---@param result any
---@return hecate.http.Response response
---@return any? failure  the error that was replaced by a problem response
local function response_of(ok, result)
  if not ok then return problem.from_error(result), result end
  if not core.is_instance_of(result, Response) then
    return problem.response(500), core.Error("http.Server: the action returned " .. type(result) .. " instead of a Response")
  end
  local content = result.content
  local kind = type(content)
  if not Status.is_valid(result.status) or not core.is_instance_of(result.fields, Fields) or type(result.reason) ~= "string" then
    return problem.response(500), core.Error("http.Server: the action returned a response with an invalid status, reason or fields")
  end
  if result.status < 200 or not (content == nil or kind == "string" or kind == "table" or kind == "function") then
    return problem.response(500), core.Error("http.Server: the action returned a response the server cannot send")
  end
  return result, nil
end

---@param action function
---@param request hecate.http.Request
---@return table outcome  `{ ok, result }`
local function call_action(action, request)
  local ok, result = pcall(action, request)
  if not ok and is_cancellation(result) then error(result, 0) end
  return { ok, result }
end

--- Builds the functions given to a response whose content is a function: `write(chunk)` codes the chunk (or counts the
--- bytes of a declared length) and sends it, `flush()` pushes what is buffered to the client, `remaining()` is for the
--- server (bytes still owed under a declared length, or nil).
local function content_writer(server, conn, mode, remaining)
  local function write(data)
    if type(data) ~= "string" then error(core.ArgumentError("http.Server: a chunk of content must be a string"), 2) end
    if data == "" then return end
    if remaining ~= nil then
      remaining = remaining - #data
      if remaining < 0 then
        error(core.ArgumentError("http.Server: more bytes written than the declared Content-Length"), 2)
      end
      send(server, conn, data)
    elseif mode == "chunked" then
      send(server, conn, wire.chunk(data))
    else
      send(server, conn, data)
    end
  end
  local function flush_content() flush(server, conn) end
  return write, flush_content, function() return remaining end
end

--- Chooses how the content is framed (RFC 9112, section 6): the mode, and its text (the content, or the length).
---@param status integer
---@param content any
---@param declared string?  a Content-Length the action set
---@param version string  protocol version of the request
---@return string mode  none, declared_only, length, declared, chunked or close_delimited
---@return string? text
local function frame(status, content, declared, version)
  local has_declared = declared ~= nil and string.find(declared, "^%d+$") ~= nil
  if status < 200 or status == 204 then return "none" end
  if status == 304 then return has_declared and "declared_only" or "none", declared end
  local kind = type(content)
  if kind == "string" then return "length", content end
  if kind == "table" then return "length", json.encode(content) end
  if kind == "function" then
    if has_declared then return "declared", declared end
    return version == "HTTP/1.0" and "close_delimited" or "chunked"
  end
  return "length", ""
end

--- Sends `response` as the answer to the request described by `info` (`method`, `version`, `keep_alive`) and returns
--- whether the connection stays open. HEAD and the statuses 1xx, 204 and 304 never carry content (RFC 9110, sections
--- 9.3.2, 15.2, 15.3.5 and 15.4.5); a function without a declared length is sent chunked (RFC 9112, section 7.1), or
--- delimited by the close for HTTP/1.0. The framing fields of the action are replaced by the server's own.
---@async
---@param info { method?: string, version: string, keep_alive: boolean }
---@param response hecate.http.Response
---@param force_close boolean
---@return boolean keep_alive
local function send_response(self, conn, info, response, force_close)
  local status = response.status
  local fields = response.fields:copy()
  local wants_close = force_close or not info.keep_alive or self._stopping
    or wire.has_connection_option(fields:combined("Connection"), "close")
  local declared = fields:get("Content-Length")
  for _, name in ipairs(HOP_BY_HOP) do fields:remove(name) end

  local mode, text = frame(status, response.content, declared, info.version)
  local head_request = info.method == "HEAD"
  if type(response.content) == "table" and mode == "length" and not fields:has("Content-Type") then
    fields:set("Content-Type", "application/json")
  end
  if mode == "length" then
    fields:set("Content-Length", tostring(#(text --[[@as string]])))
  elseif mode == "declared" or mode == "declared_only" then
    fields:set("Content-Length", text --[[@as string]])
  elseif mode == "chunked" and not head_request then
    fields:set("Transfer-Encoding", "chunked")
  elseif mode == "close_delimited" then
    wants_close = true
  end
  if not fields:has("Date") then fields:set("Date", date_now()) end
  if wants_close then
    fields:set("Connection", "close")
  elseif info.version == "HTTP/1.0" then
    fields:set("Connection", "keep-alive")
  end

  send(self, conn, wire.head(status, response.reason, fields))
  if head_request or mode == "none" or mode == "declared_only" then
    flush(self, conn)
    return not wants_close
  end
  if mode == "length" then
    send(self, conn, text --[[@as string]])
    flush(self, conn)
    return not wants_close
  end

  flush(self, conn) -- the head reaches the client now: a streamed response is useful before its end
  local write, flush_content, remaining = content_writer(self, conn, mode, mode == "declared" and math.tointeger(text) or nil)
  local ok, err = pcall(response.content --[[@as function]], write, flush_content)
  if not ok then
    if is_cancellation(err) then error(err, 0) end
    self:_report("a content writer failed", err)
    pcall(flush, self, conn) -- what was written reaches the client, which sees the content cut short
    return false -- the head is sent: the client cannot be told, the connection is closed
  end
  if mode == "declared" and remaining() ~= 0 then
    self:_report("a content writer stopped before the declared Content-Length", "short content")
    pcall(flush, self, conn)
    return false
  end
  if mode == "chunked" then send(self, conn, wire.LAST_CHUNK) end
  flush(self, conn)
  return not wants_close
end

--- Answers with problem details and reports that the connection must close. A failed write is ignored: the client is gone.
---@async
local function send_problem(self, conn, info, status, detail)
  local ok, err = pcall(send_response, self, conn, info, problem.response(status, detail), true)
  if not ok and is_cancellation(err) then error(err, 0) end
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
  local info = { method = head.method, version = head.version, keep_alive = head.keep_alive }
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
    local outcome = scope:fork(call_action, self._action, request):value()
    local response, failure = response_of(outcome[1], outcome[2])
    if failure ~= nil then self:_report("the action failed", failure) end
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
  if self._logger ~= nil and not is_cancellation(result) and not self._stopping then
    local failure = result --[[@as table]]
    local reason = core.is_instance_of(failure, core.Error) and ((failure.context and failure.context.reason) or failure.code) or "error"
    pcall(self._logger.log, self._logger, "warning", "http.Server: TLS handshake failed", {
      peer = known and (tostring(peer.ip) .. ":" .. tostring(peer.port)) or "unknown",
      reason = tostring(reason),
    })
  end
  return nil
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
    waiting = false, partial = false, in_content = false, broken = false, eof = false,
  }
  local known, peer = pcall(stream.peer_address, stream)
  conn.peer = known and peer or nil
  self._connections[conn] = true
  local ok, err = pcall(serve_connection, self, conn)
  self._connections[conn] = nil
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

---@async
local function accept_loop(self, scope)
  local listener = self._listener
  local failures = 0 -- consecutive accept failures: a burst
  while not self._stopping do
    if self._slots ~= nil then self._slots:acquire() end
    -- A handshake slot is taken before accepting: past the limit, connections wait in the kernel backlog.
    if self._tls ~= nil then self._handshakes:acquire() end
    local ok, stream = pcall(listener.accept, listener)
    if not ok then
      if self._slots ~= nil then self._slots:release() end
      if self._tls ~= nil then self._handshakes:release() end
      if self._stopping or is_cancellation(stream) or listener:is_closed() then return end
      -- Descriptor exhaustion (EMFILE, ENFILE) or another accept failure: existing connections keep serving, the
      -- loop backs off (50 ms, doubling to 1 s) instead of spinning, and the burst is reported once.
      failures = failures + 1
      if failures == 1 then
        local failure = stream --[[@as table]]
        local errno = failure.context and failure.context.errno or "error"
        if self._logger ~= nil then
          pcall(self._logger.log, self._logger, "warning", "http.Server: accept failed", { reason = tostring(errno) })
        end
        self:_report("accept failed", stream)
      end
      reactor.sleep(math.min(0.05 * 2 ^ (failures - 1), 1))
    else
      failures = 0
      scope:fork(run_connection, self, stream)
    end
  end
end

--- Binds the listening socket on the `host`, `port` and `backlog` options (suspends for the bind only) and returns
--- the listener. The default host is the numeric loopback address: serving every interface is an explicit choice
--- (`host = "0.0.0.0"` or `"::"`). Pass the listener to `serve`, or let `serve` call this.
---
--- Raises `hecate.reactor.TransportError` when the address cannot be bound.
---@async
---@return hecate.net.TcpListener
function Server:listen()
  return net.listen(self._host, self._port, { backlog = self._backlog })
end

--- Accepts connections from `listener` (bound by `listen` when omitted) and serves them until `shutdown` completes.
--- Each connection is a computation of an internal scope that ends only when every connection and request has ended;
--- a failure of a connection closes that connection only. Returns once every connection has ended.
---
--- Raises `hecate.core.ArgumentError` when already serving, a `TransportError` when binding fails, and the
--- cancellation of the caller.
---@async
---@param listener? hecate.net.TcpListener  any net listener whose `accept` returns a stream with `reader`, `writer`, `shutdown` and `close` (a `PipeListener` is expected to work and is not tested)
function Server:serve(listener)
  if self._serving then error(core.ArgumentError("http.Server:serve: the server is already serving"), 2) end
  listener = listener or self:listen()
  self._listener = listener
  self._serving = true
  local ok, err = pcall(reactor.scope, function(scope)
    self._scope = scope
    if self._stopping then return end
    self._accepting = scope:fork(accept_loop, self, scope)
  end)
  listener:close()
  self._serving = false
  self._finished:release()
  if not ok and not (self._forced and is_cancellation(err)) then error(err, 0) end
end

---@async
local function wait_finished(self)
  self._finished:acquire()
  self._finished:release() -- the next waiter
end

--- Stops accepting, closes the connections that wait for a request, lets the requests in flight finish (each answer
--- carries `Connection: close`), and returns when `serve` has returned. When `grace_timeout` seconds pass first, the
--- remaining requests are cancelled (the grace period of ADR 0023). Calling it again waits for the same end.
---
--- Raises `hecate.core.ArgumentError` for a `grace_timeout` that is not a non-negative finite number of seconds.
---@async
---@param grace_timeout? number  seconds to let requests finish (default 30)
function Server:shutdown(grace_timeout)
  if grace_timeout == nil then grace_timeout = 30 end
  if type(grace_timeout) ~= "number" or grace_timeout ~= grace_timeout or grace_timeout < 0 or grace_timeout == math.huge then
    error(core.ArgumentError("http.Server:shutdown: grace_timeout must be a non-negative finite number of seconds"), 2)
  end
  if not self._stopping then
    self._stopping = true
    if self._accepting ~= nil then self._accepting:cancel() end
    if self._listener ~= nil then self._listener:close() end
    for conn in pairs(self._connections) do
      if conn.waiting then conn.stream:close() end
    end
    for limited in pairs(self._handshaking) do limited:close() end
  end
  if not self._serving then return end
  local ok, err = pcall(reactor.deadline, grace_timeout, wait_finished, self)
  if ok then return end
  if not is_deadline(err) then error(err, 0) end
  self._forced = true
  self._scope:cancel()
  reactor.deadline(5, wait_finished, self)
end

return core.finalise(Server)
