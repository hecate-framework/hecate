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
---@param handler function
---@param options? table
---@param fn function
function support.with_server(case, handler, options, fn)
  options = options or {}
  options.port = 0
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = Server(handler, options)
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    local ok, err = pcall(reactor.deadline, 25, fn, listener:local_address().port, server)
    server:shutdown(2)
    serving:value()
    if not ok then error(err, 0) end
  end)
  case:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

return support
