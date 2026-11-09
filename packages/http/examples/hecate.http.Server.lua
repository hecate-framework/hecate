-- A server on a free port. The action answers with a string, JSON text (http never serialises) and a
-- function that streams its content, then the server shuts down.
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  if request.path == "/hello" then
    return http.Response(200, { content = "hello" })
  elseif request.path == "/user" then
    return http.Response(200, { content = json.encode({ name = "Ada" }) })
  elseif request.path == "/count" then
    return http.Response(200, {
      content = function(write)
        for i = 1, 3 do write(i .. "\n") end
      end,
    })
  end
  return http.problem.response(404)
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client()
  print(client:get(base .. "/hello"):read_content())
  print(client:get(base .. "/user"):read_content())
  print((client:get(base .. "/count"):read_content():gsub("\n", " "):gsub(" $", "")))
  print(client:get(base .. "/missing").status)
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: hello
-- {"name":"Ada"}
-- 1 2 3
-- 404
