-- `Supervisor:local_address` without worker processes: a fake strategy whose `prepare` suspends shows what a caller
-- sees while the primary's socket is not bound yet.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorUnitTest")

--- A strategy whose `prepare` waits on `gate`, then reports `address`; workers are never started (the command fails).
local function gated_strategy(gate, address)
  return {
    name = "gated",
    prepare = function(_, _) gate:receive(); return address end,
    run = function() reactor.sleep(60) end,
    close = function() end,
  }
end

--- Runs a supervisor with `endpoint`; `observe(sup, open)` runs beside it, `open()` lets `prepare` return.
local function with_gated_supervisor(endpoint, address, observe)
  local gate = reactor.Channel(1)
  local sup = kernel.supervisor.Supervisor({
    command = { "hecate-no-such-program" }, count = 1, endpoint = endpoint, strategy = gated_strategy(gate, address),
  })
  reactor.run(function()
    reactor.fork(function() observe(sup, function() gate:send(true) end) end)
    pcall(reactor.deadline, 10, sup.run, sup) -- ends with start_failed: no worker program
  end)
end

function T:test_an_ephemeral_port_is_unknown_until_the_socket_is_bound()
  local before, after
  with_gated_supervisor({ host = "127.0.0.1", port = 0 }, { ip = "127.0.0.1", port = 41234, family = "inet" },
    function(sup, open)
      reactor.sleep(0.01)
      before = sup:local_address() or false
      open()
      reactor.sleep(0)
      after = sup:local_address()
    end)
  self:assert_false(before) -- not `{ port = 0 }`, which a caller cannot connect to
  self:assert_equal(41234, after.port)
end

function T:test_a_fixed_port_is_reported_while_preparing()
  local seen
  with_gated_supervisor({ host = "127.0.0.1", port = 8123 }, nil, function(sup, open)
    reactor.sleep(0.01)
    seen = sup:local_address()
    open()
  end)
  self:assert_equal(8123, seen.port)
end

return T
