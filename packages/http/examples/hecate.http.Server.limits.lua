-- Limits, as options. A server that accepts 16 bytes of content refuses a
-- larger request with a 413 before the action runs, and the parser limits
-- go in the `parser` table.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local ran = false
local function action()
  ran = true
  return http.Response(200, { content = "ok" })
end

reactor.run(function()
  local server = http.Server(action, {
    port = 0,
    max_content = 16,
    head_timeout = 5,
    idle_timeout = 30,
    max_connections = 100,
    parser = { max_fields = 20 },
  })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local small = client:post(url, "0123456789")
  print(small.status .. " " .. small:read_content())
  -- Prints: 200 ok
  ran = false
  local large = client:post(url, ("x"):rep(17))
  print(large.status .. " " .. large.fields:get("Content-Type") .. " " .. tostring(ran))
  -- Prints: 413 application/problem+json false
  server:shutdown()
  reactor.join(serving)
end)
