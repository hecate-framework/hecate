-- The HTTP/1.1 server over hecate.net streams (RFC 9110, RFC 9112; ADR 0003; ADR 0019).
--
-- Shape: `serve` accepts connections in a scope; each connection is one computation of that scope, and each request
-- one scope of its own with one computation running the handler (concurrency.md, "Structured concurrency"). A
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
local ContentReader = require("hecate.http.content")
local problem = require("hecate.http.problem")
local wire = require("hecate.http.wire")

local ContentError = ContentReader.ContentError

--- Bytes read from a connection at once: never more than the parser's read buffer (llhttp's `feed` returns every
--- event of the chunk in one list).
local READ_SIZE <const> = 16384

--- Options of the server. Every limit has a safe default; a server never runs unbounded.
---@class hecate.http.ServerOptions
---@field host? string  a NUMERIC address, IPv4 or IPv6, for `listen` (default "127.0.0.1": the loopback interface only); a name is refused
---@field port? integer  0 to 65535 for `listen`; 0 picks a free port (default 8080)
---@field backlog? integer  pending connections the kernel queues (default 128)
---@field max_connections? integer  connections served at once (default 1024); the others wait in the backlog
---@field max_content? integer  bytes of request content (default 1048576; over it: 413)
---@field head_timeout? number  seconds to receive a request head once its first byte arrived (default 10; then 408)
---@field idle_timeout? number  seconds a connection may wait for the next request (default 60; then closed silently)
---@field content_timeout? number  seconds between two reads of request content (default 30; then 408)
---@field write_timeout? number  seconds a write to the client may take (default 30; then the connection is closed)
---@field parser? hecate.http.parser.Options  limits of the message parser (target, field, head size, field count)
---@field on_error? fun(err: any)  called with the failure of a handler or a connection (the client only sees generic problem details)

--- Defaults of the settings, exported so that documentation and tests read one source.
local DEFAULTS <const> = {
  host = "127.0.0.1",
  port = 8080,
  backlog = 128,
  max_connections = 1024,
  max_content = 1048576,
  head_timeout = 10,
  idle_timeout = 60,
  content_timeout = 30,
  write_timeout = 30,
}

--- An HTTP/1.1 server: `serve` accepts connections from a listener and answers each request with the handler.
---@class hecate.http.Server
---@field DEFAULTS table<string, any>  the defaults of the settings
---@overload fun(handler: (fun(request: hecate.http.Request): hecate.http.Response), options?: hecate.http.ServerOptions): hecate.http.Server
local Server = core.class("Server")
Server.DEFAULTS = DEFAULTS

local KNOWN <const> = {
  host = true, port = true, backlog = true, max_connections = true, max_content = true, head_timeout = true,
  idle_timeout = true, content_timeout = true, write_timeout = true, parser = true, on_error = true,
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
  error(core.ArgumentError(("http.Server: invalid %s %s: expected %s"):format(name, tostring(value), expected)), 4)
end

--- Creates a server; nothing is bound until `listen` or `serve`.
---
--- Raises `hecate.core.ArgumentError` for a handler that is not a function, an unknown or invalid option, or a host
--- that is not a numeric address (a name would bind every address the resolver lists, networking.md "TCP").
---@param handler fun(request: hecate.http.Request): hecate.http.Response  runs in its own scope, once per request
---@param options? hecate.http.ServerOptions
function Server:init(handler, options)
  if type(handler) ~= "function" then error(core.ArgumentError("http.Server: the handler must be a function"), 3) end
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
  self._handler = handler
  self._host = host
  self._port = integer("port", 0, 65535)
  self._backlog = integer("backlog", 1, 65535)
  self._max_connections = integer("max_connections", 1, 1000000)
  self._max_content = integer("max_content", 0, 1099511627776)
  self._head_timeout = seconds("head_timeout")
  self._idle_timeout = seconds("idle_timeout")
  self._content_timeout = seconds("content_timeout")
  self._write_timeout = seconds("write_timeout")
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
  self._slots = reactor.Semaphore(self._max_connections)
  self._finished = reactor.Semaphore(0)
end

--- Reports a failure to `on_error` (an error of the callback is discarded).
---@param message string
---@param err any
function Server:_report(message, err)
  local callback = self._on_error
  if callback ~= nil then
    pcall(callback, core.is_instance_of(err, core.Error) and err or core.Error({ message = message .. ": " .. tostring(err) }))
  end
end

--- The address the server listens on, `{ ip, port, family }`, or nil when it is not serving.
---@return hecate.reactor.SocketAddress?
function Server:local_address()
  return self._listener and self._listener:local_address() or nil
end

--- Whether `shutdown` was called.
---@return boolean
function Server:is_stopping() return self._stopping end

---@return boolean
local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end

local function is_deadline(err) return core.is_instance_of(err, core.DeadlineExceededError) end

-- Reading ---------------------------------------------------------------------------------------------------------

--- Reads one chunk with the deadline that fits the state of the connection.
---@async
local function read_chunk(self, conn)
  local limit
  if conn.in_content then
    limit = self._content_timeout
  elseif conn.head_started then
    limit = math.max(0, conn.head_deadline - reactor.now())
  else
    limit = self._idle_timeout
  end
  local stream = conn.stream
  local chunk = reactor.deadline(limit, stream.read, stream, READ_SIZE)
  if chunk ~= nil and not conn.in_content and not conn.head_started then
    conn.head_started = true
    conn.head_deadline = reactor.now() + self._head_timeout
  end
  return chunk
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


--- The response a handler produced, or the problem details for what went wrong. A handler must return a `Response`
--- with a final status (200 to 599) and content that is nil, a string, a table (serialised as JSON) or a function.
---@param ok boolean
---@param result any
---@return hecate.http.Response response
---@return any? failure  the error that was replaced by a problem response
local function response_of(ok, result)
  if not ok then return problem.from_error(result), result end
  if not core.is_instance_of(result, Response) then
    return problem.response(500), core.Error("http.Server: the handler returned " .. type(result) .. " instead of a Response")
  end
  local content = result.content
  local kind = type(content)
  if result.status < 200 or not (content == nil or kind == "string" or kind == "table" or kind == "function") then
    return problem.response(500), core.Error("http.Server: the handler returned a response the server cannot send")
  end
  return result, nil
end

---@param handler function
---@param request hecate.http.Request
---@return table outcome  `{ ok, result }`
local function call_handler(handler, request)
  local ok, result = pcall(handler, request)
  if not ok and is_cancellation(result) then error(result, 0) end
  return { ok, result }
end

--- Builds the functions given to a response whose content is a function: `write(chunk)` codes the chunk (or counts the
--- bytes of a declared length) and sends it, `flush()` pushes what is buffered to the client, `remaining()` is for the
--- server (bytes still owed under a declared length, or nil).
local function content_writer(server, conn, mode, remaining)
  local function write(data)
    if type(data) ~= "string" then error(core.ArgumentError("http: a chunk of content must be a string"), 2) end
    if data == "" then return end
    if remaining ~= nil then
      remaining = remaining - #data
      if remaining < 0 then
        error(core.ArgumentError("http: more bytes written than the declared Content-Length"), 2)
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
---@param declared string?  a Content-Length the handler set
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
--- delimited by the close for HTTP/1.0. The framing fields of the handler are replaced by the server's own.
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
---@return hecate.http.ContentReader
local function content_reader(self, conn, head, expecting)
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
  return ContentReader(pull, { limit = self._max_content })
end

--- The status and detail to answer a head with before any handler runs, or nil when the request may be handled.
---@param head hecate.http.parser.Head
---@return integer? status
---@return string? detail
local function refuse(self, head)
  -- RFC 9112, section 3.2: a server MUST answer 400 to an HTTP/1.1 request without exactly one Host field.
  if head.version == "HTTP/1.1" and #head.fields:get_all("Host") ~= 1 then
    return 400, "The request needs exactly one Host field."
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

--- Serves one request from its head: one scope, one computation running the handler. Returns whether the connection
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
  local reader = content_reader(self, conn, head, expecting)
  local made, request = pcall(Request, {
    method = head.method, target = head.target, fields = head.fields, version = head.version,
    peer_address = conn.peer, content_reader = reader,
  })
  if not made then
    send_problem(self, conn, info, 400, nil)
    return false
  end
  return reactor.scope(function(scope)
    request.scope = scope
    local outcome = scope:fork(call_handler, self._handler, request):value()
    local response, failure = response_of(outcome[1], outcome[2])
    if failure ~= nil then self:_report("the handler failed", failure) end
    -- A client that expects 100 Continue may still send the content the handler never asked for: close (RFC 9110, 10.1.1).
    local abandoned = expecting and not reader:is_started()
    local keep = send_response(self, conn, info, response, abandoned)
    if not keep or conn.broken or abandoned then return false end
    -- The handler left content unread: drain it (bounded by the content limit) so the next request can be parsed.
    local drained = pcall(function()
      while not reader:is_finished() do reader:read() end
    end)
    return drained and not conn.broken
  end)
end

--- Serves the requests of one connection in order until it ends.
---@async
local function serve_connection(self, conn)
  while true do
    conn.waiting, conn.head_started, conn.in_content = true, false, false
    local ok, event, failure = pcall(next_event, self, conn)
    conn.waiting = false
    if not ok then
      if is_deadline(event) and conn.head_started then
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
    local keep = serve_request(self, conn, event)
    if not keep or self._stopping then return end
  end
end

---@async
local function run_connection(self, stream)
  local conn = {
    stream = stream, writer = stream:writer(), parser = Parser.request(self._limits), queue = {}, position = 1, tail = 0,
    waiting = false, head_started = false, in_content = false, broken = false, eof = false,
  }
  local known, peer = pcall(stream.peer_address, stream)
  conn.peer = known and peer or nil
  self._connections[conn] = true
  local ok, err = pcall(serve_connection, self, conn)
  self._connections[conn] = nil
  conn.parser:close()
  if ok and not stream:is_closed() then
    -- Half-close first, so that the last bytes are not lost to a reset when the client still sends.
    pcall(reactor.deadline, 1, stream.shutdown, stream)
  end
  stream:close()
  self._slots:release()
  if not ok and not is_cancellation(err) and not self._stopping then
    self:_report("a connection ended with a failure", err)
  end
end

---@async
local function accept_loop(self, scope)
  local listener = self._listener
  while not self._stopping do
    self._slots:acquire()
    local ok, stream = pcall(listener.accept, listener)
    if not ok then
      self._slots:release()
      if self._stopping or is_cancellation(stream) or listener:is_closed() then return end
      self:_report("accept failed", stream)
      reactor.sleep(0.05) -- for example EMFILE: do not spin
    else
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
---@param listener? hecate.net.TcpListener
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
--- carries `Connection: close`), and returns when `serve` has returned. When `grace` seconds pass first, the remaining
--- requests are cancelled. Calling it again waits for the same end.
---
--- Raises `hecate.core.ArgumentError` for a `grace` that is not a non-negative finite number.
---@async
---@param grace? number  seconds to let requests finish (default 30)
function Server:shutdown(grace)
  if grace == nil then grace = 30 end
  if type(grace) ~= "number" or grace ~= grace or grace < 0 or grace == math.huge then
    error(core.ArgumentError("http.Server:shutdown: grace must be a non-negative finite number of seconds"), 2)
  end
  if not self._stopping then
    self._stopping = true
    if self._accepting ~= nil then self._accepting:cancel() end
    if self._listener ~= nil then self._listener:close() end
    for conn in pairs(self._connections) do
      if conn.waiting then conn.stream:close() end
    end
  end
  if not self._serving then return end
  local ok, err = pcall(reactor.deadline, grace, wait_finished, self)
  if ok then return end
  if not is_deadline(err) then error(err, 0) end
  self._forced = true
  self._scope:cancel()
  reactor.deadline(5, wait_finished, self)
end

return core.finalise(Server)
