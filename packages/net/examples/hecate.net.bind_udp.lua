-- A datagram exchange over the loopback interface: two sockets on free ports,
-- one datagram each way. `send_to` takes a numeric address (resolve a name
-- first with `net.resolve`), and each `receive_from` returns exactly one
-- datagram with the sender's address.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local server <close> = net.bind_udp("127.0.0.1", 0)
  local client <close> = net.bind_udp("127.0.0.1", 0)
  reactor.fork(function()
    local payload, from = server:receive_from()
    server:send_to(from.ip, from.port, payload:upper())
  end)
  client:send_to("127.0.0.1", server:local_address().port, "ping")
  local reply = client:receive_from()
  print(reply)
end)
-- Prints: PING
