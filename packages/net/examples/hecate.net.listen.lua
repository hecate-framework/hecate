-- An accept loop that forks one coroutine per connection, so that a slow client never delays the
-- others. Two clients are served at the same time; the loop is cancelled when they are done.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local function serve(connection)
  local peer <close> = connection
  local reader, writer = peer:reader(), peer:writer()
  while true do
    local line = reader:read_line()
    if line == nil then return end -- the client closed its end
    writer:write(line:upper() .. "\n")
    writer:flush()
  end
end

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local port = listener:local_address().port
  local acceptor = reactor.fork(function()
    while true do
      reactor.fork(serve, listener:accept())
    end
  end)
  local function ask(word)
    local client <close> = net.connect("127.0.0.1", port)
    local reader, writer = client:reader(), client:writer()
    writer:write(word .. "\n")
    writer:flush()
    return reader:read_line()
  end
  local first, second = reactor.join(reactor.fork(ask, "alpha"), reactor.fork(ask, "beta"))
  print(first .. " " .. second)
  acceptor:cancel()
end)
-- Prints: ALPHA BETA
