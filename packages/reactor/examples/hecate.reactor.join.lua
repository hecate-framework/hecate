-- Fork computations, then join them: `join` returns their values in
-- argument order. Inside a scope, a computation that fails cancels its
-- siblings, and the scope raises the failure once every child has ended.
local reactor = require("hecate.reactor")

local function fetch(name, seconds)
  reactor.sleep(seconds) -- stands for a request to another service
  return name .. " ready"
end

reactor.run(function()
  local users = reactor.fork(fetch, "users", 0.02)
  local orders = reactor.fork(fetch, "orders", 0.01)
  print(reactor.join(users, orders))
  -- Prints: users ready	orders ready

  local slow
  local ok, err = pcall(reactor.scope, function(scope)
    slow = scope:fork(fetch, "report", 10)
    local failing = scope:fork(function()
      reactor.sleep(0.01)
      error("no stock", 0)
    end)
    return reactor.join(slow, failing)
  end)
  print(ok, err, slow:state())
  -- Prints: false	no stock	cancelled
end)
