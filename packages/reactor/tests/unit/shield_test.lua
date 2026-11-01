local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")

local T = test.Case("ShieldTest")

local function run_virtual(fn) return reactor.Reactor({ clock = "virtual" }):run(fn) end

function T:test_cleanup_can_suspend_while_its_scope_is_cancelled()
  local flushed_at
  run_virtual(function()
    reactor.scope(function(scope)
      scope:fork(function()
        local ok = pcall(reactor.sleep, 100) -- cancelled below
        self:assert_false(ok)
        reactor.shield(5, function() reactor.sleep(1); flushed_at = reactor.now() end)
      end)
      reactor.sleep(2)
      scope:cancel()
    end)
  end)
  self:assert_equal(3, flushed_at)
end

function T:test_shield_returns_the_results_of_fn()
  local a, b = run_virtual(function() return reactor.shield(1, function(x, y) return x + y, "ok" end, 1, 2) end)
  self:assert_equal(3, a)
  self:assert_equal("ok", b)
end

function T:test_own_deadline_bounds_a_stuck_cleanup()
  local at
  run_virtual(function()
    local err = self:assert_error(function() reactor.shield(2, function() reactor.sleep(100) end) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    at = reactor.now()
  end)
  self:assert_equal(2, at)
end

function T:test_an_instant_is_accepted()
  local at
  run_virtual(function()
    self:assert_error(function() reactor.shield(reactor.at(4), function() reactor.sleep(100) end) end)
    at = reactor.now()
  end)
  self:assert_equal(4, at)
end

function T:test_outer_cancellation_is_ignored_inside_and_seen_after()
  run_virtual(function()
    local after
    reactor.scope(function(scope)
      scope:fork(function()
        reactor.shield(10, function() reactor.sleep(1); reactor.sleep(1) end) -- survives the cancel at t=0.5
        after = pcall(reactor.sleep, 1)
      end)
      reactor.sleep(0.5)
      scope:cancel()
    end)
    self:assert_equal(false, after)
    self:assert_equal(2, reactor.now())
  end)
end

function T:test_futures_cancel_of_the_computation_is_deferred_until_the_shield_ends()
  run_virtual(function()
    local trace = {}
    local future = reactor.fork(function()
      reactor.shield(10, function() reactor.sleep(1); trace[#trace + 1] = "cleaned" end)
      reactor.sleep(1) -- the cancellation requested meanwhile is raised here
      trace[#trace + 1] = "after"
    end)
    reactor.sleep(0.5)
    future:cancel()
    pcall(future.value, future)
    self:assert_equal("cleaned", trace[1])
    self:assert_nil(trace[2], "the cancellation is raised again at the next suspension point")
    self:assert_equal("cancelled", future:state())
  end)
end

function T:test_computations_forked_in_a_shield_are_not_cancelled_by_the_outer_scope()
  local finished
  run_virtual(function()
    reactor.scope(function(outer)
      outer:fork(function()
        reactor.shield(10, function()
          reactor.fork(function() reactor.sleep(1); finished = true end)
        end)
      end)
      reactor.sleep(0.5)
      outer:cancel()
    end)
  end)
  self:assert_true(finished)
end

function T:test_shields_nest_and_the_innermost_deadline_applies()
  run_virtual(function()
    local err = self:assert_error(function()
      reactor.shield(10, function() reactor.shield(1, function() reactor.sleep(5) end) end)
    end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(1, reactor.now())
  end)
end

function T:test_arguments_are_checked()
  run_virtual(function()
    for _, bad in ipairs({ 0/0, math.huge, "1", false }) do
      local err = self:assert_error(function() reactor.shield(bad, function() end) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError))
    end
    ---@diagnostic disable-next-line: param-type-mismatch  -- the argument is invalid on purpose
    local err = self:assert_error(function() reactor.shield(1, 3) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_outside_a_managed_coroutine_raises()
  local err = self:assert_error(function() reactor.shield(1, function() end) end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

return T
