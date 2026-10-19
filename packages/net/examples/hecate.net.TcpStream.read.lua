-- A deadline around a read. The server stays silent, so the read is cancelled when the deadline
-- passes. Nothing is lost: the stream and the reader are intact, and the next read gets the
-- answer when it comes. (A write cancelled by a deadline would have closed the stream.)
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local release = reactor.Channel()
  reactor.fork(function()
    local peer <close> = listener:accept()
    release:receive() -- stay silent until told to answer
    peer:write("late\n")
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader = client:reader()
  local ok, err = pcall(reactor.deadline, 0.05, function() return reader:read_line() end)
  local late = not ok and core.is_instance_of(err, core.DeadlineExceededError)
  release:send(true)
  print(("deadline exceeded: %s; then read: %s"):format(tostring(late), reader:read_line()))
end)
-- Prints: deadline exceeded: true; then read: late
