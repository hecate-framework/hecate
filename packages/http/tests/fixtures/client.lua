-- Support for the integration tests of the server (not a test): a client written over hecate.net that parses the
-- responses with the response parser, and `with_server`, which runs a server on port 0 inside the reactor and checks
-- that no libuv handle is left open. Load with `dofile` (see server_limits_test.lua).
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local Parser = require("hecate.http.parser")
local Server = require("hecate.http.server")

local support = {}

local Client = {}
Client.__index = Client

--- Connects to the server on loopback.
---@param port integer
---@return any client
function support.connect(port)
  local stream = net.connect("127.0.0.1", port)
  return setmetatable({ stream = stream, parser = Parser.response(), queue = {}, eof = false }, Client)
end

function Client:send(data) self.stream:write(data) end

--- Reads one response: `{ status, fields, content }`, or nil when the connection ended first.
---@return any
function Client:read_response()
  local response
  while true do
    while #self.queue > 0 do
      local event = table.remove(self.queue, 1)
      if event.type == "head" then
        response = { status = event.status, fields = event.fields, content = "" }
      elseif event.type == "data" then
        response.content = response.content .. event.data
      elseif event.type == "complete" then
        return response
      end
    end
    if self.eof then return response end
    local ok, chunk = pcall(reactor.deadline, 20, self.stream.read, self.stream, 65536)
    if not ok then
      self.eof = true -- reset by the peer
      chunk = nil
    end
    local events, err
    if chunk == nil then
      self.eof = true
      events, err = self.parser:finish()
    else
      events, err = self.parser:feed(chunk)
    end
    if err then return response end
    for _, event in ipairs(events) do self.queue[#self.queue + 1] = event end
  end
end

---@return any
function Client:request(text)
  self:send(text)
  return self:read_response()
end

function Client:close() self.stream:close() end
Client.__close = Client.close

--- A GET request text.
---@param path string
---@param extra? string  more field lines, each ending in CRLF
---@return string
function support.get(path, extra)
  return "GET " .. path .. " HTTP/1.1\r\nHost: test\r\n" .. (extra or "") .. "\r\n"
end

--- Runs `fn(port, server)` with a serving server on port 0 in the reactor, shuts it down, and asserts that no libuv
--- handle is left open.
---@param case table  the test case (for the assertion)
---@param action function
---@param options? table
---@param fn function
function support.with_server(case, action, options, fn)
  options = options or {}
  options.port = 0
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = Server(action, options)
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    local ok, err = pcall(reactor.deadline, 25, fn, listener:local_address().port, server)
    server:shutdown(2)
    serving:value()
    if not ok then error(err, 0) end
  end)
  case:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

--- Runs `fn` on a reactor under a 30 s deadline and asserts that no libuv handle is left open.
---@param case table
---@param fn function
function support.run(case, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(function() reactor.deadline(30, fn) end)
  case:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

--- Reads one request head from a stream (until the blank line); nil at the end of the stream.
---@param stream any
---@return string?
function support.read_head(stream)
  local buffer = ""
  while not buffer:find("\r\n\r\n", 1, true) do
    local chunk = stream:read()
    if chunk == nil then return nil end
    buffer = buffer .. chunk
  end
  return buffer
end

--- A scripted server: `script(stream, index)` runs for each accepted connection (`index` counts them); the stream is closed
--- when it returns. Returns `{ port, accepted, stop }`; `accepted` counts the connections taken so far.
---@param script fun(stream: any, index: integer)
---@return table
function support.scripted(script)
  local listener = net.listen("127.0.0.1", 0)
  local state = { accepted = 0, port = listener:local_address().port }
  local loop = reactor.fork(function()
    while true do
      local ok, stream = pcall(listener.accept, listener)
      if not ok then return end
      state.accepted = state.accepted + 1
      local index = state.accepted
      reactor.fork(function()
        pcall(script, stream, index)
        stream:close()
      end)
    end
  end)
  function state.stop()
    listener:close()
    loop:cancel()
  end
  return state
end

--- The response text of a 200 with `content`.
---@param content string
---@return string
function support.ok(content)
  return "HTTP/1.1 200 OK\r\nContent-Length: " .. #content .. "\r\n\r\n" .. content
end

return support
