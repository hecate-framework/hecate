-- A client with its pool. The server echoes what it receives; the client
-- sends JSON, then reads a response chunk by chunk and releases its
-- connection.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local content = request:read_content()
  return http.Response(200, { content = request.method .. " " .. request.path .. " " .. #content })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client({ request_timeout = 10 })

  local created = client:post(base .. "/items", { name = "pen" })
  print(created.status .. " " .. created:read_content())
  -- Prints: 200 POST /items 14

  local response <close> = client:get(base .. "/items/7")
  local stream = response:stream_content()
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    print(chunk)
  end
  -- Prints: GET /items/7 0

  server:shutdown()
  reactor.join(serving)
end)
