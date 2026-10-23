-- An echo exchange over the loopback interface: a listener on a free port, a
-- client that connects to it, one line each way.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line() .. "!\n")
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: hello!
