-- A failed verification raises a `TlsError` whose `context.reason` names the
-- kind of failure. Here the client trusts only another authority than the one
-- that signed the server's certificate. Needs the native TLS module
-- (`lua tools/run.lua build-native`).
local core = require("hecate.core")
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
    -- The client abandons the handshake.
    local ok = pcall(net.tls.accept, listener:accept(), config)
    assert(not ok)
  end)
  local ok, err = pcall(net.connect_tls, "localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("other_ca.pem"), system_roots = false,
  })
  assert(not ok and core.is_instance_of(err, net.TlsError))
  -- An error value, not the stream that `pcall` is typed to return.
  ---@cast err any
  print(err.context.reason)
end)
-- Prints: untrusted_issuer
