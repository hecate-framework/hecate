-- A CPU-bound function runs on the libuv thread pool while the reactor keeps serving
-- other computations. The function is self-contained: what it needs arrives as
-- arguments, and its results are copied back.
local reactor = require("hecate.reactor")

reactor.run(function()
  local ticks = 0
  local ticker = reactor.fork(function()
    while true do
      reactor.sleep(0.001)
      ticks = ticks + 1 -- counted after a completed sleep: the reactor was free meanwhile
    end
  end)
  local count, largest = reactor.offload(function(limit)
    -- The primes below `limit`, by trial division: deliberately slow work.
    local primes = {}
    for n = 2, limit do
      local prime = true
      for d = 2, math.floor(math.sqrt(n)) do
        if n % d == 0 then prime = false; break end
      end
      if prime then primes[#primes + 1] = n end
    end
    return #primes, primes[#primes]
  end, 200000)
  ticker:cancel()
  print(("%d primes, the largest is %d, the reactor ticked: %s"):format(count, largest, tostring(ticks > 0)))
end)
-- Prints: 17984 primes, the largest is 199999, the reactor ticked: true
