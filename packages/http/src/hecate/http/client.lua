-- The HTTP/1.1 client over hecate.net streams (RFC 9110, RFC 9112): a connection pool per origin, redirects, deadlines,
-- TLS and streaming in both directions. One request is one computation of the caller's scope: cancelling the scope
-- cancels the request, and the connection of a cancelled request is dropped, never reused.
global <const> require, type, error, pcall, pairs, ipairs, math, string, tostring, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local json = require("hecate.json")
local Parser = require("hecate.http.parser")
local Fields = require("hecate.http.fields")
local Response = require("hecate.http.response")
local Status = require("hecate.http.status")
local ContentStream = require("hecate.http.content")
local grammar = require("hecate.http.grammar")
local url = require("hecate.http.url")
local form = require("hecate.http.form")
local multipart = require("hecate.http.multipart")
local wire = require("hecate.http.wire")

local READ_SIZE <const> = 16384

--- Settings of a client and their defaults. Every limit has one.
---@class hecate.http.ClientOptions
---@field connect_timeout? number  seconds to connect and, for https, to handshake (default 10)
---@field head_timeout? number  seconds from the end of the request to the end of the response head (default 30)
---@field content_timeout? number  seconds between two reads of response content (default 60)
---@field write_timeout? number  seconds a write to the server may take (default 60)
---@field request_timeout? number  seconds for the whole exchange, redirects and content included (default 300; overridden per request; a streaming download longer than that sets a larger value)
---@field max_content? integer  bytes `response:read_content()` accepts (default 10485760, 10 MiB)
---@field max_redirects? integer  redirects followed per request (default 10)
---@field allow_downgrade? boolean  follow a redirect from https to http (default false)
---@field max_connections_per_origin? integer  connections to one origin, in use or idle (default 8)
---@field max_idle_connections? integer  idle connections in the whole pool (default 64; the least recently used is closed beyond it)
---@field cross_origin_redirects? boolean  follow a 307 or 308 to another origin when it would send the request content again (default false)
---@field strip_on_redirect? string[]  more field names removed when a redirect changes the origin (always removed: Authorization, Cookie, Proxy-Authorization, X-Api-Key, X-Auth-Token)
---@field idle_timeout? number  seconds a pooled connection may idle (default 30: shorter than the 75 s of `http.Server`)
---@field expect_timeout? number  seconds to wait for `100 Continue` when a request asks for it (default 1)
---@field user_agent? string  the `User-Agent` field (default "hecate-http")
---@field tls? { ca_pem?: string, system_roots?: boolean, cert_pem?: string, key_pem?: string }  trust and client certificate for https (ADR 0024: the system store by default; `ca_pem` adds an anchor)
---@field parser? hecate.http.parser.Options  limits on the response head (target is unused; field size, head size, field count)

--- The defaults of the client's settings. Settings without an entry have no default value: `tls` (the system trust store),
--- `strip_on_redirect` (only the built-in list) and `parser` (the parser's own limits).
---@class hecate.http.ClientDefaults
---@field connect_timeout number
---@field head_timeout number
---@field content_timeout number
---@field write_timeout number
---@field request_timeout number
---@field max_content integer
---@field max_redirects integer
---@field allow_downgrade boolean
---@field max_connections_per_origin integer
---@field max_idle_connections integer
---@field cross_origin_redirects boolean
---@field idle_timeout number
---@field expect_timeout number
---@field user_agent string

---@type hecate.http.ClientDefaults
local DEFAULTS <const> = {
  connect_timeout = 10,
  head_timeout = 30,
  content_timeout = 60,
  write_timeout = 60,
  max_content = 10485760,
  max_redirects = 10,
  allow_downgrade = false,
  max_connections_per_origin = 8,
  max_idle_connections = 64,
  request_timeout = 300,
  cross_origin_redirects = false,
  idle_timeout = 30,
  expect_timeout = 1,
  user_agent = "hecate-http",
}

--- An HTTP/1.1 client with a pool of connections per origin.
---@class hecate.http.Client
---@field DEFAULTS hecate.http.ClientDefaults
---@overload fun(options?: hecate.http.ClientOptions): hecate.http.Client
local Client = core.class("Client")
Client.DEFAULTS = DEFAULTS

-- The options of one request (the other settings belong to the client).
local REQUEST_OPTIONS <const> = {
  fields = true, content = true, form = true, multipart = true, redirects = true, expect_continue = true,
  cross_origin_redirects = true, request_timeout = true, head_timeout = true, content_timeout = true, max_content = true,
  max_redirects = true,
}

local KNOWN <const> = {
  connect_timeout = true, head_timeout = true, content_timeout = true, write_timeout = true, request_timeout = true,
  max_content = true, max_redirects = true, allow_downgrade = true, max_connections_per_origin = true,
  idle_timeout = true, expect_timeout = true, user_agent = true, tls = true, parser = true,
  max_idle_connections = true, cross_origin_redirects = true, strip_on_redirect = true,
}

local function bad(name, expected, value)
  error(core.ArgumentError(("http.Client: invalid %s: expected %s"):format(name, expected)), 4)
end

--- Creates a client. Nothing is connected until the first request.
---
--- Raises `hecate.core.ArgumentError` for an unknown or invalid option.
---@param options? hecate.http.ClientOptions
function Client:init(options)
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Client: options must be a table"), 3) end
  for key in pairs(options) do
    if not KNOWN[key] then error(core.ArgumentError(("http.Client: unknown option %s"):format(tostring(key))), 3) end
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
  ---@return integer
  local function integer(name, minimum, maximum)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as integer]] end
    if math.type(value) ~= "integer" or value < minimum or value > maximum then
      bad(name, ("an integer from %d to %d"):format(minimum, maximum), value)
    end
    return value
  end
  self._connect_timeout = seconds("connect_timeout")
  self._head_timeout = seconds("head_timeout")
  self._content_timeout = seconds("content_timeout")
  self._write_timeout = seconds("write_timeout")
  self._idle_timeout = seconds("idle_timeout")
  self._expect_timeout = seconds("expect_timeout")
  self._request_timeout = seconds("request_timeout")
  self._max_content = integer("max_content", 0, 1099511627776)
  self._max_redirects = integer("max_redirects", 0, 100)
  self._max_per_origin = integer("max_connections_per_origin", 1, 10000)
  self._max_idle = integer("max_idle_connections", 0, 100000)
  for _, name in ipairs({ "cross_origin_redirects" }) do
    if options[name] ~= nil and type(options[name]) ~= "boolean" then bad(name, "a boolean", options[name]) end
  end
  self._cross_origin_redirects = options.cross_origin_redirects or false
  local strip = { "Authorization", "Cookie", "Proxy-Authorization", "X-Api-Key", "X-Auth-Token" }
  if options.strip_on_redirect ~= nil then
    if type(options.strip_on_redirect) ~= "table" then bad("strip_on_redirect", "a list of field names", options.strip_on_redirect) end
    for _, name in ipairs(options.strip_on_redirect) do
      if not grammar.is_token(name) then bad("strip_on_redirect", "a list of field names (tokens)", tostring(name)) end
      strip[#strip + 1] = name
    end
  end
  self._strip_on_redirect = strip
  if options.allow_downgrade ~= nil and type(options.allow_downgrade) ~= "boolean" then
    bad("allow_downgrade", "a boolean", options.allow_downgrade)
  end
  self._allow_downgrade = options.allow_downgrade or false
  local agent = options.user_agent
  if agent == nil then agent = DEFAULTS.user_agent end
  if not grammar.is_field_value(agent) or agent == "" then bad("user_agent", "a non-empty string without CR, LF or NUL", agent) end
  self._user_agent = agent
  -- A table of `net.tls.client_config` options, or a configuration that function built (a native userdata: `net` offers
  -- no class to test an instance against, and checks the same way).
  if options.tls ~= nil and type(options.tls) ~= "table" and type(options.tls) ~= "userdata" then
    bad("tls", "a table of TLS client options or a configuration built by net.tls.client_config", options.tls)
  end
  self._tls_options = type(options.tls) == "table" and options.tls or nil
  self._tls_config = type(options.tls) == "userdata" and options.tls or nil
  if options.parser ~= nil then Parser.response(options.parser):close() end -- validates the limits now
  self._limits = options.parser
  self._origins = {}
  self._closed = false
end

-- Connections -----------------------------------------------------------------------------------------------------

---@class hecate.http.client.Connection
---@field stream any
---@field parser hecate.http.Parser
---@field queue table
---@field position integer
---@field tail integer
---@field eof boolean
---@field failure any
---@field received integer  bytes read since the connection was opened
---@field last_used number
---@field reusable boolean

local function discard(conn)
  if conn.dead then return end
  conn.dead = true
  conn.parser:close()
  conn.stream:close()
end

--- The seconds left of the whole-request deadline, or math.huge.
local function remaining(state)
  if state.deadline_at == nil then return math.huge end
  return state.deadline_at - reactor.now()
end

--- `seconds` limited by the whole-request deadline (at least 0: an expired deadline fails at the first suspension).
local function bounded(state, seconds)
  return math.max(0, math.min(seconds, remaining(state)))
end

---@async
local function read_chunk(conn, seconds)
  local stream = conn.stream
  local chunk = reactor.deadline(seconds, stream.read, stream, READ_SIZE)
  if chunk ~= nil then conn.received = conn.received + #chunk end
  return chunk
end

--- The next parser event of the connection, or nil and a reason (a `ParseError`, or "eof"). Waits at most `seconds`.
---@async
local function next_event(conn, seconds)
  while true do
    local event = conn.queue[conn.position]
    if event ~= nil then
      conn.queue[conn.position] = nil
      conn.position = conn.position + 1
      return event
    end
    if conn.failure ~= nil then return nil, conn.failure end
    if conn.eof then return nil, "eof" end
    local chunk = read_chunk(conn, seconds)
    local events, err
    if chunk == nil then
      conn.eof = true
      events, err = conn.parser:finish()
    else
      events, err = conn.parser:feed(chunk)
    end
    for _, parsed in ipairs(events) do
      conn.tail = conn.tail + 1
      conn.queue[conn.tail] = parsed
    end
    if err ~= nil and chunk ~= nil then conn.failure = err end
  end
end

local function end_of_stream(message)
  return net.EndOfStreamError({ message = "http.Client: " .. message, context = { buffered = 0 } })
end

---@return table
function Client:_tls_client_config()
  if self._tls_config == nil then
    local config = {}
    for key, value in pairs(self._tls_options or {}) do config[key] = value end
    config.alpn = { "http/1.1" }
    self._tls_config = net.tls.client_config(config)
  end
  return self._tls_config
end

---@async
function Client:_connect(parts, state)
  local seconds = bounded(state, self._connect_timeout)
  local stream
  if parts.scheme == "https" then
    local config = self:_tls_client_config()
    stream = reactor.deadline(seconds, net.connect_tls, parts.host, parts.port, {
      tls_config = config, handshake_timeout = math.max(seconds, 0.001),
    })
  else
    stream = reactor.deadline(seconds, net.connect, parts.host, parts.port)
  end
  return {
    stream = stream, parser = Parser.response(self._limits), queue = {}, position = 1, tail = 0, eof = false,
    received = 0, last_used = reactor.now(), reusable = true,
  }
end

local function origin_of(self, origin)
  local entry = self._origins[origin]
  if entry == nil then
    entry = { idle = {}, leases = reactor.Semaphore(self._max_per_origin) }
    self._origins[origin] = entry
  end
  return entry
end

--- A pooled connection is usable when it is open, has not idled too long, and nothing arrived on it (a closed peer shows
--- as the end of stream; bytes nobody asked for are a protocol violation). It tries a read that expires at once, so it
--- belongs to the computations that may suspend.
---@async
local function alive(self, conn)
  if conn.stream:is_closed() or conn.eof or conn.failure ~= nil then return false end
  if reactor.now() - conn.last_used > self._idle_timeout then return false end
  if conn.tail >= conn.position or conn.parser:in_message() then return false end -- bytes nobody asked for
  local ok, chunk = pcall(reactor.deadline, 0, conn.stream.read, conn.stream, 1)
  if ok then return false end -- the end of the stream, or stray bytes
  return core.is_instance_of(chunk, core.DeadlineExceededError) -- nothing arrived: alive
end

local sweep -- defined below, with the pool's other bookkeeping

--- Takes a lease on the origin (waits when `max_connections_per_origin` are leased), then a pooled connection or a new one.
---@async
---@return hecate.http.client.Connection conn
---@return boolean reused
function Client:_checkout(parts, state)
  sweep(self)
  local entry = origin_of(self, parts.origin)
  local wait = remaining(state)
  if wait == math.huge then
    entry.leases:acquire()
  else
    reactor.deadline(math.max(0, wait), entry.leases.acquire, entry.leases)
  end
  local ok, conn, reused = pcall(function()
    while #entry.idle > 0 do
      local candidate = table.remove(entry.idle)
      if alive(self, candidate) then return candidate, true end
      discard(candidate)
    end
    return self:_connect(parts, state), false
  end)
  if not ok then
    entry.leases:release()
    error(conn, 0)
  end
  conn.origin, conn.lease_entry = parts.origin, entry
  return conn, reused
end

--- Closes the idle connections that expired or were closed, in every origin; forgets the origins that have no idle
--- connection and no lease; then closes the least recently used idle connections beyond `max_idle_connections`.
function sweep(self)
  local now, count = reactor.now(), 0
  for origin, entry in pairs(self._origins) do
    local keep = {}
    for _, conn in ipairs(entry.idle) do
      if now - conn.last_used > self._idle_timeout or conn.stream:is_closed() or conn.dead then discard(conn) else keep[#keep + 1] = conn end
    end
    entry.idle = keep
    count = count + #keep
    if #keep == 0 and entry.leases:available() == self._max_per_origin and entry.leases:waiting() == 0 then
      self._origins[origin] = nil
    end
  end
  while count > self._max_idle do
    local oldest, holder
    for _, entry in pairs(self._origins) do
      for _, conn in ipairs(entry.idle) do
        if oldest == nil or conn.last_used < oldest.last_used then oldest, holder = conn, entry end
      end
    end
    if oldest == nil then break end
    for i, conn in ipairs(holder.idle) do
      if conn == oldest then table.remove(holder.idle, i) break end
    end
    discard(oldest)
    count = count - 1
  end
end

--- Returns a connection after its response was read: pooled when reusable, dropped otherwise; releases the lease.
local function checkin(self, conn)
  local entry = conn.lease_entry
  conn.lease_entry = nil
  if entry == nil then return end
  conn.last_used = reactor.now()
  if conn.reusable and not self._closed and not conn.dead and not conn.eof and conn.failure == nil and conn.tail < conn.position
    and not conn.parser:in_message() then
    entry.idle[#entry.idle + 1] = conn
  else
    discard(conn)
  end
  entry.leases:release()
  sweep(self)
end

--- The size of the pool: `idle` connections and the `origins` it keeps an entry for.
---@return { idle: integer, origins: integer }
function Client:pool_stats()
  local idle, origins = 0, 0
  for _, entry in pairs(self._origins) do
    idle = idle + #entry.idle
    origins = origins + 1
  end
  return { idle = idle, origins = origins }
end

local function drop(conn)
  local entry = conn.lease_entry
  conn.lease_entry = nil
  discard(conn)
  if entry ~= nil then entry.leases:release() end
end

-- One exchange ----------------------------------------------------------------------------------------------------

local IDEMPOTENT <const> = { GET = true, HEAD = true, PUT = true, DELETE = true, OPTIONS = true, TRACE = true }

local function protocol_error(message, reason)
  return core.ProtocolError({ message = "http.Client: " .. message, context = { reason = reason } })
end

---@async
local function write(self, conn, state, data)
  if data == "" then return end
  reactor.deadline(bounded(state, self._write_timeout), conn.stream.write, conn.stream, data)
end

--- Writes the request: the head, then the content (a string with its length, a function chunked).
---@async
local function write_request(self, conn, state, method, parts, fields, content)
  local head = { method, " ", parts.target, " HTTP/1.1\r\nHost: ", parts.authority, "\r\n" }
  for name, value in fields:lines() do head[#head + 1] = name .. ": " .. value .. "\r\n" end
  if type(content) == "string" then
    head[#head + 1] = "Content-Length: " .. #content .. "\r\n"
  elseif type(content) == "function" then
    head[#head + 1] = "Transfer-Encoding: chunked\r\n"
  elseif method == "POST" or method == "PUT" or method == "PATCH" then
    head[#head + 1] = "Content-Length: 0\r\n"
  end
  head[#head + 1] = "\r\n"
  local text = table.concat(head)
  local expecting = state.expect and content ~= nil
  if expecting then
    write(self, conn, state, text)
    -- RFC 9110 section 10.1.1: wait for 100 Continue, or a final status that makes the content useless, or give up. Other
    -- interim responses (102, 103) are skipped; a connection that ends meanwhile is a failure.
    local give_up = reactor.now() + self._expect_timeout
    while true do
      local ok, event, err = pcall(next_event, conn, bounded(state, math.max(0, give_up - reactor.now())))
      if not ok then
        if core.is_instance_of(event, core.DeadlineExceededError) then break end
        error(event, 0)
      end
      if event == nil then
        if err == "eof" then error(end_of_stream("the connection closed before the request content was sent"), 0) end
        error(err, 0)
      end
      if event.type == "head" and event.status == 100 then
        next_event(conn, bounded(state, self._expect_timeout)) -- its `complete`
        break
      elseif event.type == "head" and event.status < 200 then
        next_event(conn, bounded(state, self._expect_timeout)) -- skip it and its `complete`
      elseif event.type == "head" then
        conn.early = event -- a final answer: the content is not sent and the connection not reused
        conn.reusable = false
        return
      else
        error(protocol_error("unexpected data while waiting for 100 Continue", "unexpected_data"), 0)
      end
    end
    text = ""
  end
  if type(content) == "string" then
    write(self, conn, state, text .. content)
  elseif type(content) == "function" then
    write(self, conn, state, text)
    local function send(chunk)
      if type(chunk) ~= "string" then error(core.ArgumentError("http.Client: a chunk of content must be a string"), 2) end
      write(self, conn, state, wire.chunk(chunk))
    end
    content(send)
    write(self, conn, state, wire.LAST_CHUNK)
  else
    write(self, conn, state, text)
  end
end

--- Reads the response head, skipping interim responses.
---@async
local function read_head(self, conn, state, method)
  local limit = reactor.now() + state.head_timeout
  local skip_complete = false
  while true do
    local event, err
    if conn.early ~= nil then
      event, conn.early = conn.early, nil
    else
      event, err = next_event(conn, bounded(state, math.max(0, limit - reactor.now())))
    end
    if event == nil then
      if err == "eof" then
        if conn.received == 0 then error(end_of_stream("the connection closed before the response"), 0) end
        error(end_of_stream("the connection closed inside the response head"), 0)
      end
      error(err, 0)
    end
    if event.type == "head" then
      if not Status.is_valid(event.status) then
        error(core.ProtocolError({ message = "http.Client: the response status is not a valid status code", context = { reason = "status" } }), 0)
      end
      -- OQ-67: the reason phrase carries no control character (RFC 9112 section 4); llhttp lets them through.
      if event.reason ~= nil and string.find(event.reason, "[%c\127]") and not string.find(event.reason, "^[\t%g ]*$") then
        error(core.ProtocolError({ message = "http.Client: the response reason phrase holds control characters", context = { reason = "reason_phrase" } }), 0)
      end
      if event.status == 101 then
        error(core.ProtocolError({ message = "http.Client: unexpected 101 Switching Protocols", context = { reason = "upgrade" } }), 0)
      end
      if event.status >= 200 then return event end
      skip_complete = true
    elseif event.type == "complete" and skip_complete then
      skip_complete = false
    elseif event.type == "upgrade" then
      error(core.ProtocolError({ message = "http.Client: the response switches protocols", context = { reason = "upgrade" } }), 0)
    else
      error(core.ProtocolError({ message = "http.Client: unexpected data before the response head", context = { reason = "unexpected_data" } }), 0)
    end
  end
end

--- Builds the response: its content stream pulls from the connection, which goes back to the pool when the content ends.
---@param head hecate.http.parser.Head
local function make_response(self, conn, state, head, final_url)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    if head.keep_alive and not wire.has_connection_option(state.fields:combined("Connection"), "close") then
      checkin(self, conn)
    else
      drop(conn)
    end
  end
  local function pull()
    if finished then return nil end
    while true do
      local ok, event, err = pcall(next_event, conn, bounded(state, state.content_timeout))
      if not ok then
        drop(conn)
        finished = true
        error(event, 0)
      end
      if event == nil then
        drop(conn)
        finished = true
        if err == "eof" then error(end_of_stream("the connection closed inside the response content"), 0) end
        error(err, 0)
      end
      if event.type == "data" then return event.data end
      if event.type == "complete" then
        finish()
        return nil
      end
      drop(conn)
      finished = true
      error(core.ProtocolError({ message = "http.Client: unexpected event in the response content", context = { reason = "unexpected_event" } }), 0)
    end
  end
  local stream = ContentStream(pull, { limit = state.max_content }) -- max_content bounds `read_content` and `stream_content` alike
  local response = Response(head.status, {
    reason = head.reason, fields = head.fields, content_stream = stream, max_content = state.max_content,
    discard = function()
      if not finished then
        finished = true
        drop(conn)
      end
    end,
  })
  response.url = final_url
  -- No content (HEAD, 204, 304, a zero length): the message is complete already, give the connection back now.
  local nxt = conn.queue[conn.position]
  if nxt ~= nil and nxt.type == "complete" then
    conn.queue[conn.position] = nil
    conn.position = conn.position + 1
    finish()
    stream = nil
    response._content_stream = ContentStream.of("")
  end
  return response
end

--- One request and its response head on a pooled or new connection, retried once on a new connection when a reused one
--- turns out dead before any byte of the response arrived (idempotent methods and replayable content only).
---@async
function Client:_exchange(parts, method, fields, content, state, final_url)
  local replayable = content == nil or type(content) == "string"
  for attempt = 1, 2 do
    local conn, reused = self:_checkout(parts, state)
    state.fields = fields
    conn.received = 0 -- counts the bytes of this exchange: a failure before any is safe to retry
    if method == "HEAD" then conn.parser:skip_content() end
    if wire.has_connection_option(fields:combined("Connection"), "close") then conn.reusable = false end
    local ok, result = pcall(function()
      write_request(self, conn, state, method, parts, fields, content)
      return read_head(self, conn, state, method)
    end)
    if ok then return make_response(self, conn, state, result, final_url) end
    local failure_before_bytes = conn.received == 0
    drop(conn)
    local transient = core.is_instance_of(result, core.NetworkError)
    if not (reused and attempt == 1 and IDEMPOTENT[method] and replayable and failure_before_bytes and transient) then
      error(result, 0)
    end
  end
end

-- Requests and redirects ------------------------------------------------------------------------------------------

local ENTITY_FIELDS <const> = { "Content-Type", "Content-Length", "Content-Encoding", "Content-Language", "Content-Location", "Transfer-Encoding", "Expect" }

--- Sends a request and returns the response once its head has arrived; the content is read through
--- `response:read_content()` or `response:stream_content()`. The response holds its connection until the content is read
--- to its end or the response is closed. Redirects (301, 302, 303, 307, 308) are followed up to `max_redirects`.
---
--- `options`: `cross_origin_redirects` (this request may repeat its content to another origin on a 307 or 308), `form` (pairs, sent as `application/x-www-form-urlencoded`), `multipart` (parts for `multipart.build`, sent as
--- `multipart/form-data` with a random boundary; a function part streams the message, which is then not replayable), `fields` (a `Fields`, or a table for `Fields`), `content` (a string, sent with its length; a function
--- `content(write)`, streamed chunked and never replayed; a table, serialised as JSON), `redirects` (false: return the 3xx
--- response), `expect_continue` (send `Expect: 100-continue` and wait before the content; default false), `request_timeout`
--- (this request's total seconds, overrides the client's), and `head_timeout`, `content_timeout`, `max_content` and `max_redirects`
--- (this request's values of those settings). An unknown key is an `ArgumentError`.
---
--- Raises `hecate.core.ArgumentError` for an invalid method, URL (relative, userinfo, whitespace, control characters),
--- field or option; `hecate.reactor.TransportError` (as `net` raises it: its message and context may name the addresses
--- the name resolved to, so never forward them to a peer), `hecate.core.DeadlineExceededError`,
--- `hecate.net.EndOfStreamError`, `hecate.http.ParseError` and `hecate.core.ProtocolError` (a refused reason phrase,
--- too many redirects, a redirect loop, a downgrade to http) for failures.
---@async
---@param method string
---@param target string  an absolute http or https URL
---@param options? { fields?: hecate.http.Fields|table, content?: string|table|function, form?: string[][], multipart?: table[], cross_origin_redirects?: boolean, head_timeout?: number, content_timeout?: number, max_content?: integer, max_redirects?: integer, redirects?: boolean, expect_continue?: boolean, request_timeout?: number }
---@return hecate.http.Response
function Client:request(method, target, options)
  if self._closed then error(core.Error("http.Client:request: the client is closed"), 2) end
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Client:request: options must be a table"), 2) end
  if not grammar.is_token(method) then error(core.ArgumentError("http.Client:request: the method must be a token"), 2) end
  for key in pairs(options) do
    if not REQUEST_OPTIONS[key] then error(core.ArgumentError(("http.Client:request: unknown option %s"):format(tostring(key))), 2) end
  end
  local parts, reason = url.parse(target)
  if parts == nil then error(core.ArgumentError("http.Client:request: invalid URL: " .. tostring(reason)), 2) end
  local fields
  if type(options.fields) == "table" and core.is_instance_of(options.fields, Fields) then
    fields = options.fields:copy()
  else
    fields = Fields(options.fields)
  end
  for _, name in ipairs({ "Host", "Content-Length", "Transfer-Encoding" }) do fields:remove(name) end
  if not fields:has("User-Agent") then fields:set("User-Agent", self._user_agent) end
  local content = options.content
  if (options.form ~= nil and 1 or 0) + (options.multipart ~= nil and 1 or 0) + (content ~= nil and 1 or 0) > 1 then
    error(core.ArgumentError("http.Client:request: content, form and multipart exclude each other"), 2)
  end
  if options.form ~= nil then
    content = form.encode_urlencoded(options.form)
    if not fields:has("Content-Type") then fields:set("Content-Type", "application/x-www-form-urlencoded") end
  elseif options.multipart ~= nil then
    local built, content_type = multipart.build(options.multipart)
    content = built
    fields:set("Content-Type", content_type)
  elseif type(content) == "table" then
    content = json.encode(content)
    if not fields:has("Content-Type") then fields:set("Content-Type", "application/json") end
  elseif content ~= nil and type(content) ~= "string" and type(content) ~= "function" then
    error(core.ArgumentError("http.Client:request: content must be a string, a table or a function"), 2)
  end
  local function per_request(name, kind)
    local value = options[name]
    if value == nil then return self["_" .. name] end
    if kind == "seconds" and (type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge) then
      error(core.ArgumentError(("http.Client:request: %s must be a positive finite number of seconds"):format(name)), 3)
    end
    if kind == "count" and (math.type(value) ~= "integer" or value < 0) then
      error(core.ArgumentError(("http.Client:request: %s must be a non-negative integer"):format(name)), 3)
    end
    return value
  end
  local total = options.request_timeout or self._request_timeout
  if total ~= nil and (type(total) ~= "number" or total ~= total or total <= 0 or total == math.huge) then
    error(core.ArgumentError("http.Client:request: request_timeout must be a positive finite number of seconds"), 2)
  end
  local state = {
    deadline_at = total ~= nil and (reactor.now() + total) or nil, expect = options.expect_continue == true,
    head_timeout = per_request("head_timeout", "seconds"), content_timeout = per_request("content_timeout", "seconds"),
    max_content = per_request("max_content", "count"), max_redirects = per_request("max_redirects", "count"),
  }
  local visited = {}
  for hop = 0, state.max_redirects do
    local response = self:_exchange(parts, method, fields, content, state, parts.origin .. parts.target)
    local status = response.status
    local location = response.fields:get("Location")
    local follows = options.redirects ~= false and location ~= nil
      and (status == 301 or status == 302 or status == 303 or status == 307 or status == 308)
    if not follows then return response end
    -- 307 and 308 repeat the request: only when the content can be sent again.
    if (status == 307 or status == 308) and type(content) == "function" then return response end
    if hop == state.max_redirects then
      response:close()
      error(protocol_error("more than " .. state.max_redirects .. " redirects", "too_many_redirects"), 0)
    end
    local absolute, why = url.resolve(parts, location)
    local nxt = absolute and url.parse(absolute)
    if nxt == nil then
      response:close()
      error(protocol_error("the Location of a redirect is not usable: " .. tostring(why or "invalid URL"), "bad_location"), 0)
    end
    if parts.scheme == "https" and nxt.scheme == "http" and not self._allow_downgrade then
      response:close()
      error(protocol_error("a redirect from https to http is refused", "downgrade"), 0)
    end
    -- A 307 or 308 repeats the request, content included: to another origin only when the caller said so (the content
    -- may be a secret that the first server chose to hand over, not the second).
    if (status == 307 or status == 308) and content ~= nil and nxt.origin ~= parts.origin
      and not (options.cross_origin_redirects or self._cross_origin_redirects) then
      return response
    end
    local new_method = method
    if status == 303 and method ~= "GET" and method ~= "HEAD" then
      new_method = "GET"
    elseif (status == 301 or status == 302) and method == "POST" then
      new_method = "GET" -- RFC 9110 section 15.4.2 and 15.4.3: what user agents do
    end
    if new_method ~= method then
      content = nil
      for _, name in ipairs(ENTITY_FIELDS) do fields:remove(name) end
    end
    if nxt.origin ~= parts.origin then
      for _, name in ipairs(self._strip_on_redirect) do fields:remove(name) end
    end
    local key = new_method .. " " .. nxt.origin .. nxt.target
    if visited[key] then
      response:close()
      error(protocol_error("redirect loop at " .. nxt.origin .. nxt.target, "redirect_loop"), 0)
    end
    visited[parts.origin .. parts.target] = true
    visited[key] = true
    response:close()
    method, parts = new_method, nxt
  end
  error(protocol_error("redirects exhausted", "too_many_redirects"), 0) -- not reached
end

---@param options? table
---@param content any
---@return table
local function with_content(options, content)
  local merged = {}
  for key, value in pairs(options or {}) do merged[key] = value end
  merged.content = content
  return merged
end

--- `request("GET", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:get(target, options) return self:request("GET", target, options) end

--- `request("HEAD", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:head(target, options) return self:request("HEAD", target, options) end

--- `request("DELETE", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:delete(target, options) return self:request("DELETE", target, options) end

--- `request("OPTIONS", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:options(target, options) return self:request("OPTIONS", target, options) end

--- `request("POST", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:post(target, content, options) return self:request("POST", target, with_content(options, content)) end

--- `request("PUT", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:put(target, content, options) return self:request("PUT", target, with_content(options, content)) end

--- `request("PATCH", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:patch(target, content, options) return self:request("PATCH", target, with_content(options, content)) end

--- Closes the idle pooled connections; connections in use are closed when their response ends. Idempotent, never
--- suspends; also the `<close>` protocol. A closed client refuses requests.
function Client:close()
  self._closed = true
  for _, entry in pairs(self._origins) do
    for _, conn in ipairs(entry.idle) do discard(conn) end
    entry.idle = {}
  end
end

--- Closes at the end of a `<close>` scope.
function Client:__close() self:close() end

return core.finalise(Client)
