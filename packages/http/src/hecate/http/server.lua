-- The HTTP/1.1 server over hecate.net (RFC 9112): one coroutine per connection, one scope per request,
-- keep-alive, pipelining (responses in request order), `Expect: 100-continue`, chunked responses, HEAD without content
-- and graceful shutdown. The parser (llhttp) frames the messages; this module never parses bytes itself.
global <const> require, type, error, pcall, string, table, os, ipairs, pairs, tostring, math

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local Parser = require("hecate.http.parser")
local Request = require("hecate.http.request")
local Response = require("hecate.http.response")
local Status = require("hecate.http.status")

local READ_SIZE = 16384
local KNOWN_OPTIONS = { max_content = true, parser = true, on_error = true }

--- Options of the server.
---@class hecate.http.ServerOptions
---@field max_content? integer  largest request content accepted, bytes (default 1048576; over it: 413 and the connection closes)
---@field parser? hecate.http.parser.Options  limits of the message parser
---@field on_error? fun(err: any)  called with the failure of a handler (the client only sees a generic 500)

--- An HTTP/1.1 server: `serve` accepts connections from a listener and answers each request with the handler.
---@class hecate.http.Server
---@overload fun(handler: (fun(request: hecate.http.Request): hecate.http.Response), options?: hecate.http.ServerOptions): hecate.http.Server
local Server = core.class("Server")

--- Creates a server.
---
--- Raises `hecate.core.ArgumentError` when `handler` is not a function or an option is unknown or invalid.
---@param handler fun(request: hecate.http.Request): hecate.http.Response  runs in its own scope, once per request
---@param options? hecate.http.ServerOptions
function Server:init(handler, options)
  if type(handler) ~= "function" then error(core.ArgumentError("http.Server: the handler must be a function"), 3) end
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Server: options must be a table"), 3) end
  for key in pairs(options) do
    if not KNOWN_OPTIONS[key] then error(core.ArgumentError("http.Server: unknown option " .. tostring(key)), 3) end
  end
  local max_content = options.max_content or 1048576
  if math.type(max_content) ~= "integer" or max_content < 0 then
    error(core.ArgumentError("http.Server: max_content must be a non-negative integer"), 3)
  end
  self._handler = handler
  self._max_content = max_content
  self._parser_options = options.parser
  self._on_error = options.on_error
  self._closing = false
  self._listener = nil
  self._connections = {} -- stream -> true while idle (waiting for a request), false while serving one
end

-- The Date field (RFC 9110 section 6.6.1), recomputed once per second.
local date_second, date_value = -1, ""
local function http_date()
  local now = os.time()
  if now ~= date_second then
    date_second, date_value = now, tostring(os.date("!%a, %d %b %Y %H:%M:%S GMT", now))
  end
  return date_value
end

--- Serialises the head of a response.
local function head_of(response, extra)
  local lines = { string.format("HTTP/1.1 %d %s\r\n", response.status, response.reason) }
  for name, value in response.fields:lines() do lines[#lines + 1] = name .. ": " .. value .. "\r\n" end
  for _, line in ipairs(extra) do lines[#lines + 1] = line .. "\r\n" end
  lines[#lines + 1] = "\r\n"
  return table.concat(lines)
end

-- Writes a response. `head_only` for HEAD (RFC 9110 section 9.3.2). Returns whether the connection may stay open.
local function write_response(writer, response, head_only, keep_alive)
  local extra = {}
  local fields = response.fields
  if not fields:has("Date") then extra[#extra + 1] = "Date: " .. http_date() end
  if not keep_alive then extra[#extra + 1] = "Connection: close" end
  local content = response.content
  local bodiless = Status.forbids_content(response.status)
  if bodiless then
    writer:write(head_of(response, extra))
  elseif type(content) == "function" then
    -- A writer function streams the content in chunks (RFC 9112 section 7.1).
    extra[#extra + 1] = "Transfer-Encoding: chunked"
    writer:write(head_of(response, extra))
    if not head_only then
      content(function(chunk)
        if type(chunk) ~= "string" then error(core.ArgumentError("http: a chunk of content must be a string"), 2) end
        if chunk ~= "" then writer:write(string.format("%x\r\n", #chunk) .. chunk .. "\r\n") end
      end)
      writer:write("0\r\n\r\n")
    end
  else
    if content ~= nil and type(content) ~= "string" then
      error(core.ArgumentError("http: the content of a response must be a string or a function at the server"), 0)
    end
    content = content or ""
    if not fields:has("Content-Length") then extra[#extra + 1] = "Content-Length: " .. #content end
    writer:write(head_of(response, extra))
    if not head_only then writer:write(content) end
  end
  writer:flush()
end

local function simple(status, reason_text)
  return Response(status, { content = reason_text, fields = require("hecate.http.fields")({
    ["Content-Type"] = "text/plain; charset=utf-8",
  }) })
end

-- Runs the handler in its own scope; any failure becomes a generic 500 (nothing of the error reaches the client).
local function dispatch(self, request)
  local ok, result = pcall(reactor.scope, function(scope)
    request.scope = scope
    return self._handler(request)
  end)
  if ok and core.is_instance_of(result, Response) then return result end
  if self._on_error then
    pcall(self._on_error, ok and core.ArgumentError("http.Server: the handler must return a Response") or result)
  end
  return simple(500, "Internal Server Error")
end

-- The connection loop. Returns when the connection ends.
local function serve_connection(self, stream)
  local writer = stream:writer()
  local parser = Parser.request(self._parser_options)
  local peer = stream:peer_address()
  ---@type hecate.http.Request?
  local current
  local body, size, too_large, fail_status = nil, 0, false, nil
  self._connections[stream] = true

  -- Handles one event; returns false when the connection must close.
  local function handle(event)
    if event.type == "head" then
      self._connections[stream] = false
      local fields = event.fields
      size, too_large, body = 0, false, {}
      local hosts = fields:get_all("Host")
      if event.version == "HTTP/1.1" and #hosts ~= 1 then
        fail_status = 400 -- RFC 9112 section 3.2: exactly one Host field in an HTTP/1.1 request
        return false
      end
      if event.content_length and event.content_length > self._max_content then
        fail_status = 413
        return false
      end
      local expect = fields:get("Expect")
      if expect ~= nil then
        if string.lower(expect) == "100-continue" and event.version == "HTTP/1.1" then
          writer:write("HTTP/1.1 100 Continue\r\n\r\n")
          writer:flush()
        else
          fail_status = 417
          return false
        end
      end
      current = Request({ method = event.method, target = event.target, version = event.version, fields = fields, peer_address = peer })
      current.keep_alive = event.keep_alive and not self._closing
    elseif event.type == "data" then
      size = size + #event.data
      if size > self._max_content then
        fail_status = 413
        return false
      end
      body[#body + 1] = event.data
    elseif event.type == "complete" then
      local request = current
      if request == nil or body == nil then return false end
      request.content = table.concat(body)
      current, body = nil, nil
      local response = dispatch(self, request)
      local keep = request.keep_alive and not self._closing
      write_response(writer, response, request.method == "HEAD", keep)
      if not keep then return false end
      self._connections[stream] = true
    end
    return true
  end

  local function refuse(status)
    pcall(function()
      local response = simple(status, Status.reason(status) or "")
      write_response(writer, response, false, false)
    end)
  end

  local running = true
  while running do
    local chunk = stream:read(READ_SIZE)
    local events, err
    if chunk == nil then
      events, err = parser:finish()
      running = false
    else
      events, err = parser:feed(chunk)
    end
    for _, event in ipairs(events) do
      if not handle(event) then
        running = false
        break
      end
    end
    if fail_status then
      refuse(fail_status)
      break
    end
    if err and running then
      refuse(err.context.status)
      break
    end
  end
  parser:close()
  pcall(writer.close, writer)
end

--- Accepts connections from `listener` and serves them until `shutdown` is called or the calling computation is
--- cancelled. Returns once every connection has finished. Suspends. One computation per connection, none of which
--- can fail the others: a failure of a connection closes that connection only.
---@async
---@param listener hecate.net.TcpListener
function Server:serve(listener)
  if self._listener ~= nil then error(core.ArgumentError("http.Server:serve: the server is already serving"), 2) end
  self._listener = listener
  reactor.scope(function(scope)
    while not self._closing do
      local ok, stream = pcall(listener.accept, listener)
      if not ok then
        if self._closing then break end
        error(stream, 0)
      end
      scope:fork(function()
        local conn <close> = stream
        pcall(serve_connection, self, conn)
        self._connections[conn] = nil
      end)
    end
  end)
  self._listener = nil
end

--- Stops accepting, closes the idle connections and lets each running request finish its response, after which its
--- connection closes (`Connection: close`). `serve` returns when they are done. Idempotent.
function Server:shutdown()
  if self._closing then return end
  self._closing = true
  if self._listener then self._listener:close() end
  for stream, idle in pairs(self._connections) do
    if idle then stream:close() end
  end
end

return core.finalise(Server)
