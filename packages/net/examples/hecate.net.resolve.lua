-- Name resolution. `resolve` returns the numeric addresses of a host in the resolver's order;
-- `family` keeps one kind. `UdpSocket:send_to` takes a numeric address only, so a datagram to a
-- name goes through `resolve` first.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local addresses = net.resolve("localhost", { family = "inet" })
  local socket <close> = net.bind_udp("127.0.0.1", 0)
  socket:send_to(addresses[1].ip, socket:local_address().port, "hello")
  local payload = socket:receive_from()
  print(addresses[1].ip .. " " .. payload)
end)
-- Prints: 127.0.0.1 hello
