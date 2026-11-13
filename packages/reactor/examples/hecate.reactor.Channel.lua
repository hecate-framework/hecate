-- A channel carries values from producers to consumers. A full channel
-- suspends its sender (back-pressure); a closed one is drained, then
-- `receive` raises `ClosedChannelError`.
local core = require("hecate.core")
local reactor = require("hecate.reactor")

reactor.run(function()
  local queue = reactor.Channel(2) -- holds at most two values
  local producer = reactor.fork(function()
    for n = 1, 5 do queue:send(n) end
    queue:close()
  end)
  local sum = 0
  while true do
    local ok, value = pcall(queue.receive, queue)
    if not ok then
      print(core.name(value))
      -- Prints: ClosedChannelError
      break
    end
    sum = sum + value
  end
  reactor.join(producer)
  print(sum)
  -- Prints: 15
end)
