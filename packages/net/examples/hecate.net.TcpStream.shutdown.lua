-- A half-close. The client sends its request, then calls `shutdown` to say that
-- nothing more follows; it can still read. The server reads until the end of
-- the stream, then answers.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    local size = 0
    while true do
      local chunk = reader:read_some(4096)
      if chunk == nil then break end -- the client's half-close
      size = size + #chunk
    end
    writer:write(("received %d bytes\n"):format(size))
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  client:write(("x"):rep(1000))
  client:shutdown() -- no more data from this side; the stream stays readable
  print(client:reader():read_line())
end)
-- Prints: received 1000 bytes
