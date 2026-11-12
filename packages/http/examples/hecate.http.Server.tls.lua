-- Serve HTTPS with the throwaway keys of the net tests (use your own
-- certificate and key) and call it with a client that trusts their CA.
-- The paths are relative to the root of the repository.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function read(name)
  local file = assert(io.open("packages/net/tests/fixtures/" .. name, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

local function action() return http.Response(200, { content = "secure" }) end

reactor.run(function()
  local server = http.Server(action, { port = 0, tls = { cert_pem = read("server.pem"), key_pem = read("server.key") } })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client({ tls = { ca_pem = read("ca.pem"), system_roots = false } })
  print(client:get("https://127.0.0.1:" .. listener:local_address().port .. "/"):read_content())
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: secure
