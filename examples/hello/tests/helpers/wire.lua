-- Raw HTTP/1.1 over a `hecate.net` stream, for the tests that need to
-- control when each byte is sent (a request still in flight when the
-- shutdown begins). Loaded with `dofile` by the tests of the example; not
-- part of the example.
local net = require("hecate.net")

local wire = {}

--- Opens a connection to the loopback interface.
---@async
---@param port integer
function wire.connect(port) return net.connect("127.0.0.1", port) end

--- Reads one response from `stream`, with the bytes already read in
--- `buffer` (returned with what is left after it).
--- Returns nil when the connection ends before a complete response.
---@async
---@param stream table
---@param buffer? string
---@return { status: integer, head: string, body: string }? response
---@return string rest
function wire.read_response(stream, buffer)
  buffer = buffer or ""
  local function more()
    local ok, data = pcall(stream.read, stream)
    if not ok or data == nil then return false end
    buffer = buffer .. data
    return true
  end
  while not buffer:find("\r\n\r\n", 1, true) do
    if not more() then return nil, buffer end
  end
  local head_end = buffer:find("\r\n\r\n", 1, true)
  local head = buffer:sub(1, head_end - 1)
  local status = tonumber(head:match("^HTTP/1%.1 (%d%d%d)"))
  local length = tonumber(head:lower():match("\r\ncontent%-length:%s*(%d+)"))
  local start = head_end + 4
  -- No content (RFC 9112, section 6.3).
  if status ~= nil and (status < 200 or status == 204 or status == 304) then
    return { status = status, head = head, body = "" }, buffer:sub(start)
  end
  -- No length: the body ends with the connection.
  if length == nil then
    while more() do end
    return { status = status, head = head, body = buffer:sub(start) }, ""
  end
  while #buffer < start + length - 1 do
    if not more() then return nil, buffer end
  end
  return { status = status, head = head, body = buffer:sub(start, start + length - 1) }, buffer:sub(start + length)
end

--- The head of a request with JSON content of `length` bytes.
---@param method string
---@param path string
---@param length? integer
---@param extra? string[]  more field lines, such as "Connection: close"
---@return string
function wire.head(method, path, length, extra)
  local lines = { ("%s %s HTTP/1.1"):format(method, path), "Host: 127.0.0.1" }
  for _, line in ipairs(extra or {}) do lines[#lines + 1] = line end
  if length then
    lines[#lines + 1] = "Content-Type: application/json"
    lines[#lines + 1] = ("Content-Length: %d"):format(length)
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

--- Whether a new connection to `port` is refused (a successful probe is
--- closed).
---@async
---@param port integer
---@return boolean
function wire.refused(port)
  local ok, stream = pcall(net.connect, "127.0.0.1", port)
  if ok then stream:close() end
  return not ok
end

--- Whether the server closed `stream` (end of stream or error) before
--- `seconds` passed.
---@async
local function closed_within(reactor, stream, seconds)
  local ok, result = pcall(reactor.deadline, seconds, function()
    while true do
      local read_ok, data = pcall(stream.read, stream)
      if not read_ok or data == nil then return true end
    end
  end)
  return ok and result == true
end

--- The scenario of the exit criterion "graceful shutdown drains in-flight
--- requests", against an application listening on `port`, with no timing
--- guess:
---
--- 1. `idle` kept-alive connections each serve `GET /health` and stay open
---    (with `round_robin` workers, consecutive connections go to
---    consecutive workers, so twice the number of workers covers each one).
---    A server closes such an idle connection as soon as its shutdown
---    begins (`http.Server:shutdown`): their end is the signal that every
---    server is draining.
--- 2. A `POST /greetings` with `Expect: 100-continue` sends its head; the
---    server answers `100 Continue` when the action's content is first
---    read: the request is then in flight, inside the action, with its
---    content not sent yet.
--- 3. `stop()` begins the shutdown, in a computation of its own; new
---    connections become refused, and the idle connections end.
--- 4. The content is sent; the answer must be complete (`201`,
---    `Connection: close`).
---
--- Returns the final response of the request in flight (nil when it got
--- none), whether new connections were refused during the drain, and
--- whether every idle connection was closed before the content was sent.
---@async
---@param reactor table  hecate.reactor
---@param port integer
---@param idle integer  idle kept-alive connections to watch (at least 1)
---@param stop fun()  begins the shutdown (it may suspend until the drain ends)
---@return { status: integer, head: string, body: string }? response
---@return boolean refused_during_drain
---@return boolean idle_closed
function wire.request_in_flight_during_shutdown(reactor, port, idle, stop)
  local watched = {}
  for i = 1, idle do
    local stream = wire.connect(port)
    stream:write(wire.head("GET", "/health"))
    local answer = wire.read_response(stream)
    assert(answer and answer.status == 200, "an idle connection served its first request")
    watched[i] = stream
  end
  local content = '{"name":"Ada","language":"es"}'
  local stream = wire.connect(port)
  stream:write(wire.head("POST", "/greetings", #content, { "Expect: 100-continue" }))
  local interim, rest = wire.read_response(stream)
  assert(interim and interim.status == 100, "the server asks for the content: the request is in flight")
  reactor.fork(stop)
  local refused = false
  -- At most about 10 seconds (a refusal takes up to 2 seconds on Windows).
  for _ = 1, 200 do
    if wire.refused(port) then refused = true break end
    reactor.sleep(0.05)
  end
  local idle_closed = true
  for _, watched_stream in ipairs(watched) do
    if not closed_within(reactor, watched_stream, 10) then idle_closed = false end
    watched_stream:close()
  end
  stream:write(content)
  local response = wire.read_response(stream, rest)
  stream:close()
  return response, refused, idle_closed
end

return wire
