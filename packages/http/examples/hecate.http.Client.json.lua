-- Call a JSON API and decode the answer. The API is a local server here;
-- with a real one only the URL changes.
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local http = require("hecate.http")

local function action(request)
  -- http never serialises: the action encodes the table and names its
  -- media type
  return http.Response(200, {
    content = json.encode({ id = 42, name = "Ada" }),
    fields = http.Fields({ { "Content-Type", "application/json" } }),
  })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/users/42")
  local user = response:read_json()
  print(response.status .. " " .. user.name)
  -- Prints: 200 Ada
  server:shutdown()
  reactor.join(serving)
end)
