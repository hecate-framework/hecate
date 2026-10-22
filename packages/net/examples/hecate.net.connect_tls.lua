-- A TLS client against a local server whose certificate comes from the test CA
-- of this package. With no option, `connect_tls` verifies the server against
-- the operating system's trust store; here `ca_pem` names the private CA and
-- `system_roots = false` trusts nothing else. Verification cannot be disabled.
-- Needs the native TLS module (`lua tools/run.lua build-native`).
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
  local config = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local reader, writer = peer:reader(), peer:writer()
    writer:write("secure " .. reader:read_line() .. "\n")
    writer:flush()
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: secure hello
