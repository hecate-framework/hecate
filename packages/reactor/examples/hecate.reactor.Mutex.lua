-- Coroutines run one at a time, but a read-modify-write that spans a
-- suspension point can interleave with another one. A mutex makes the
-- sequence exclusive; its permit is released when it goes out of scope.
local reactor = require("hecate.reactor")

reactor.run(function()
  local balance = 100
  local function withdraw(amount)
    local current = balance
    reactor.sleep(0.001) -- a suspension point: another coroutine runs
    balance = current - amount
  end
  reactor.join(reactor.fork(withdraw, 30), reactor.fork(withdraw, 20))
  print(balance) -- one update is lost
  -- Prints: 80

  balance = 100
  local mutex = reactor.Mutex()
  local function withdraw_exclusively(amount)
    local permit <close> = mutex:lock()
    local current = balance
    reactor.sleep(0.001)
    balance = current - amount
  end
  reactor.join(reactor.fork(withdraw_exclusively, 30),
    reactor.fork(withdraw_exclusively, 20))
  print(balance)
  -- Prints: 50
end)
