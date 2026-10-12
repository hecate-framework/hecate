local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("FutureTest")

function T:test_fork_returns_a_pending_future_that_completes()
  support.run_virtual(function()
    local f = reactor.fork(function() return 1, 2 end)
    self:assert_true(core.is_instance_of(f, reactor.Future))
    self:assert_equal("pending", f:state())
    self:assert_false(f:done())
    local a, b = f:value()
    self:assert_equal(1, a)
    self:assert_equal(2, b)
    self:assert_equal("completed", f:state())
    self:assert_true(f:done())
  end)
end

function T:test_fork_passes_arguments()
  local result = support.run_virtual(function()
    return reactor.fork(function(a, b) return a + b end, 3, 4):value()
  end)
  self:assert_equal(7, result)
end

function T:test_a_forked_coroutine_runs_only_when_the_parent_suspends()
  local log = {}
  support.run_virtual(function()
    local f = reactor.fork(function() log[#log + 1] = "child" end)
    log[#log + 1] = "parent"
    f:value()
  end)
  self:assert_equal("parent,child", table.concat(log, ","))
end

function T:test_value_raises_the_error_of_a_failed_future()
  local err = self:assert_error(function()
    support.run_virtual(function()
      local f = reactor.fork(function() error(core.ValidationError("bad")) end)
      f:value()
    end)
  end)
  self:assert_true(core.is_instance_of(err, core.ValidationError))
end

function T:test_failed_state_is_observable_and_the_failure_reaches_the_scope()
  local observed
  local err = self:assert_error(function()
    support.run_virtual(function()
      local f = reactor.fork(function() error("boom", 0) end)
      local ok, raised = pcall(f.value, f)
      observed = { ok = ok, raised = raised, state = f:state() }
    end)
  end)
  self:assert_equal("boom", err) -- rule 2: the failure of a child always propagates upwards
  self:assert_false(observed.ok)
  self:assert_equal("boom", observed.raised)
  self:assert_equal("failed", observed.state)
end

function T:test_cancel_a_sleeping_future()
  support.run_virtual(function()
    local f = reactor.fork(function() reactor.sleep(100) end)
    reactor.sleep(1)
    self:assert_true(f:cancel())
    local ok, err = pcall(f.value, f)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.CancellationError))
    self:assert_equal("cancelled", f:state())
    self:assert_false(f:cancel())
  end)
end

function T:test_cancel_is_delivered_at_the_next_suspension_point_only()
  local progress = {}
  support.run_virtual(function()
    local f = reactor.fork(function()
      progress[#progress + 1] = "start"
      for _ = 1, 1000 do end -- pure computation never yields
      progress[#progress + 1] = "computed"
      reactor.sleep(1)
      progress[#progress + 1] = "unreachable"
    end)
    reactor.sleep(0)
    f:cancel() -- the child is suspended in sleep(1)
    pcall(f.value, f)
  end)
  self:assert_equal("start,computed", table.concat(progress, ","))
end

function T:test_cancel_before_start_cancels_at_first_suspension()
  local ran = false
  support.run_virtual(function()
    local f = reactor.fork(function() reactor.sleep(1); ran = true end)
    f:cancel()
    pcall(f.value, f)
    self:assert_equal("cancelled", f:state())
  end)
  self:assert_false(ran)
end

function T:test_a_computation_that_ignores_cancellation_completes_normally()
  support.run_virtual(function()
    local f = reactor.fork(function() return "done" end)
    f:cancel()
    self:assert_equal("done", f:value())
    self:assert_equal("completed", f:state())
  end)
end

return T
