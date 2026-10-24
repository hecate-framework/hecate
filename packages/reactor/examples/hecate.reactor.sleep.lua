-- Two computations sleep for different durations; the shorter sleep ends first,
-- whatever the order in which they were forked.
local reactor = require("hecate.reactor")

reactor.run(function()
  local order = {}
  local slow = reactor.fork(function()
    reactor.sleep(0.05)
    order[#order + 1] = "slow"
  end)
  local fast = reactor.fork(function()
    reactor.sleep(0.01)
    order[#order + 1] = "fast"
  end)
  reactor.join(slow, fast)
  print(table.concat(order, ","))
end)
-- Prints: fast,slow
