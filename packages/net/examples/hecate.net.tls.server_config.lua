-- A TLS server that requires client certificates (mutual TLS). `client_ca_pem`
-- names the authority that signed the client certificates. The accept loop
-- forks the handshake of each connection and bounds it with
-- `handshake_timeout`, so that one silent client cannot stall it. Needs the
-- native TLS module (`lua tools/run.lua build-native`).
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
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), client_ca_pem = fixture("ca.pem"),
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  local acceptor = reactor.fork(function()
    while true do
      local connection = listener:accept()
      reactor.fork(function()
        -- The handshake owns `connection`: it is closed if the handshake fails.
        local ok, peer = pcall(net.tls.accept, connection, config, { handshake_timeout = 5 })
        if not ok then return end
        local reader, writer = peer:reader(), peer:writer()
        writer:write("welcome " .. reader:read_line() .. "\n")
        writer:flush()
        peer:read() -- until the client's close_notify
        peer:close()
      end)
    end
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
    cert_pem = fixture("client.pem"), key_pem = fixture("client.key"),
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("alice\n")
  writer:flush()
  print(reader:read_line())
  client:shutdown()
  acceptor:cancel()
end)
-- Prints: welcome alice
