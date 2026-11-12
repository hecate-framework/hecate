-- Raw HTTP/1.1 over a `hecate.net` stream, for the tests that need to control when each byte is sent (a request still
-- in flight when the shutdown begins). Loaded with `dofile` by the tests of the example; not part of the example.
local net = require("hecate.net")

local wire = {}

--- Opens a connection to the loopback interface.
---@async
---@param port integer
function wire.connect(port) return net.connect("127.0.0.1", port) end

--- Reads one response from `stream`, with the bytes already read in `buffer` (returned with what is left after it).
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
  if length == nil then -- no length: the body ends with the connection
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
---@param close? boolean  adds `Connection: close`
---@return string
function wire.head(method, path, length, close)
  local lines = { ("%s %s HTTP/1.1"):format(method, path), "Host: 127.0.0.1" }
  if close then lines[#lines + 1] = "Connection: close" end
  if length then
    lines[#lines + 1] = "Content-Type: application/json"
    lines[#lines + 1] = ("Content-Length: %d"):format(length)
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

--- Whether a new connection to `port` is refused (a successful probe is closed).
---@async
---@param port integer
---@return boolean
function wire.refused(port)
  local ok, stream = pcall(net.connect, "127.0.0.1", port)
  if ok then stream:close() end
  return not ok
end

--- The scenario of the exit criterion "graceful shutdown drains in-flight requests", against an application listening
--- on `port`: a first request on a kept-alive connection proves that a server owns the connection; the head and half of
--- the content of a `POST /greetings` follow; `stop()` begins the shutdown; once new connections are refused, the rest of
--- the content is sent. Returns the response of the request in flight, nil when it got none, and whether the port was
--- refused before the rest of the content was sent.
---@async
---@param reactor table  hecate.reactor
---@param port integer
---@param stop fun()  begins the shutdown (it may suspend until the drain ends: it runs in a computation of its own)
---@return { status: integer, head: string, body: string }? response
---@return boolean refused_during_drain
function wire.request_in_flight_during_shutdown(reactor, port, stop)
  local stream = wire.connect(port)
  stream:write(wire.head("GET", "/health"))
  local first, rest = wire.read_response(stream)
  assert(first and first.status == 200, "the first request on the connection is answered")
  local content = '{"name":"Ada","language":"es"}'
  local half = #content // 2
  stream:write(wire.head("POST", "/greetings", #content) .. content:sub(1, half))
  reactor.sleep(0.2) -- lets the server read the head; a head not read yet is still served (`http.Server:shutdown`)
  reactor.fork(stop)
  local refused = false
  for _ = 1, 200 do -- at most about 10 seconds
    if wire.refused(port) then refused = true break end
    reactor.sleep(0.05)
  end
  stream:write(content:sub(half + 1))
  local response = wire.read_response(stream, rest)
  stream:close()
  return response, refused
end

return wire
