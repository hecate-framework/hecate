-- The server side of TLS, in the two-step form that is the idiom: accept the
-- TCP connection, then run the handshake of that one connection. A server forks
-- the handshake per connection (inside `reactor.deadline`) so that one silent
-- client cannot stall the accept loop; this example handles a single connection
-- inline. Needs the native TLS module (`lua tools/run.lua build-native`).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), alpn = { "echo" },
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local line = peer:reader():read_line()
    peer:write(("%s over %s\n"):format(line, peer:alpn()))
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false, alpn = { "echo" },
  })
  client:write("hello\n")
  print(client:reader():read_line())
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: hello over echo
