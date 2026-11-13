-- An action that reads a urlencoded form. The client sends pairs with
-- `form`; a name that repeats keeps its order.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local form = request:read_form({ max_pairs = 50 })
  local tags = table.concat(form:get_all("tag"), ",")
  return http.Response(200, { content = form:get("name") .. " " .. tags })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local response = client:post(url, nil, {
    form = { { "name", "Ada Lovelace" }, { "tag", "math" }, { "tag", "code" } },
  })
  print(response:read_content())
  -- Prints: Ada Lovelace math,code
  server:shutdown()
  reactor.join(serving)
end)
