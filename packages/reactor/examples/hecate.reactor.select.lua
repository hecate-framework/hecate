-- `select` waits for the first of several alternatives and cancels the
-- futures that lost. `deadline` bounds a computation in time.
local core = require("hecate.core")
local reactor = require("hecate.reactor")

local function fetch(name, seconds)
  reactor.sleep(seconds)
  return name
end

reactor.run(function()
  -- The first mirror to answer wins; the other one is cancelled.
  local index, value = reactor.select(
    reactor.fork(fetch, "mirror-a", 0.05),
    reactor.fork(fetch, "mirror-b", 0.01))
  print(index, value)
  -- Prints: 2	mirror-b

  -- A channel operation is an alternative too: here, a stop request.
  local jobs, stop = reactor.Channel(0), reactor.Channel(0)
  reactor.fork(function() stop:send("stop") end)
  print(reactor.select(jobs:receive_op(), stop:receive_op()))
  -- Prints: 2	stop

  -- `deadline` returns the results of the function, or raises when late.
  print(reactor.deadline(1, fetch, "in time", 0.01))
  -- Prints: in time
  local ok, err = pcall(reactor.deadline, 0.01, fetch, "late", 10)
  print(ok, core.name(err))
  -- Prints: false	DeadlineExceededError
end)
