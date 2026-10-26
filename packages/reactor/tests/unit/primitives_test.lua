local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("PrimitivesTest")

function T:test_sleep_advances_the_virtual_clock_exactly()
  local elapsed = support.run_virtual(function()
    local start = reactor.now()
    reactor.sleep(1.5)
    reactor.sleep(2)
    return reactor.now() - start
  end)
  self:assert_equal(3.5, elapsed)
end

function T:test_sleeping_coroutines_wake_in_time_order_then_fork_order()
  local log = {}
  support.run_virtual(function()
    for _, spec in ipairs({ { "c", 3 }, { "a", 1 }, { "b2", 2 }, { "b1", 2 } }) do
      reactor.fork(function() reactor.sleep(spec[2]); log[#log + 1] = spec[1] end)
    end
  end)
  self:assert_equal("a,b2,b1,c", table.concat(log, ","))
end

function T:test_sleep_zero_yields_to_ready_coroutines()
  local log = {}
  support.run_virtual(function()
    reactor.fork(function() log[#log + 1] = "other" end)
    reactor.sleep(0)
    log[#log + 1] = "main"
  end)
  self:assert_equal("other,main", table.concat(log, ","))
end

function T:test_sleep_rejects_invalid_durations()
  support.run_virtual(function()
    for _, bad in ipairs({ -1, "1", 0 / 0, math.huge }) do
      local err = self:assert_error(function() reactor.sleep(bad) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError))
    end
  end)
end

function T:test_join_returns_values_in_argument_order()
  local a, b, c = support.run_virtual(function()
    local slow = reactor.fork(function() reactor.sleep(3); return "slow" end)
    local fast = reactor.fork(function() reactor.sleep(1); return "fast" end)
    local instant = reactor.fork(function() return "instant" end)
    return reactor.join(slow, fast, instant)
  end)
  self:assert_equal("slow", a)
  self:assert_equal("fast", b)
  self:assert_equal("instant", c)
end

function T:test_join_failure_cancels_the_others_and_the_scope_raises_the_first_error()
  local seen = {}
  local err = self:assert_error(function()
    support.run_virtual(function()
      local slow = reactor.fork(function()
        seen.survivor_cancelled = not pcall(reactor.sleep, 100)
      end)
      local failing = reactor.fork(function() reactor.sleep(1); error("join failure", 0) end)
      -- join raises the first error itself; the scope raises it again (rule 2).
      local ok, raised = pcall(reactor.join, slow, failing)
      seen.ok = ok
      seen.raised = raised
      seen.now = reactor.now()
    end)
  end)
  self:assert_equal("join failure", err)
  self:assert_false(seen.ok)
  self:assert_equal("join failure", seen.raised)
  self:assert_equal(1, seen.now)
  self:assert_true(seen.survivor_cancelled)
end

function T:test_select_returns_the_first_and_cancels_the_others()
  support.run_virtual(function()
    local slow = reactor.fork(function() reactor.sleep(10); return "slow" end)
    local fast = reactor.fork(function() reactor.sleep(2); return "fast" end)
    local index, value = reactor.select(slow, fast)
    self:assert_equal(2, index)
    self:assert_equal("fast", value)
    self:assert_equal(2, reactor.now())
    reactor.sleep(0)
    self:assert_equal("cancelled", slow:state())
  end)
end

function T:test_select_on_an_already_done_future_returns_immediately()
  support.run_virtual(function()
    local f = reactor.fork(function() return "v" end)
    f:value()
    local index, value = reactor.select(reactor.fork(function() reactor.sleep(5) end), f)
    self:assert_equal(2, index)
    self:assert_equal("v", value)
  end)
end

function T:test_select_on_a_failed_future_surfaces_the_failure()
  local err = self:assert_error(function()
    support.run_virtual(function()
      local failing = reactor.fork(function() error("select failure", 0) end)
      local other = reactor.fork(function() reactor.sleep(5) end)
      reactor.select(other, failing)
    end)
  end)
  self:assert_equal("select failure", err)
end

function T:test_join_and_select_validate_arguments()
  support.run_virtual(function()
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.join(1) end), core.ArgumentError))
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.select() end), core.ArgumentError))
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.fork(1) end), core.ArgumentError))
  end)
end

function T:test_watchers_of_a_finished_wait_do_not_wake_a_later_suspension()
  support.run_virtual(function()
    local first = reactor.fork(function() reactor.sleep(1) end)
    local second = reactor.fork(function() reactor.sleep(2); return "late" end)
    local index = reactor.select(first, second)
    self:assert_equal(1, index)
    -- `second` was cancelled; its completion must not cut this sleep short.
    reactor.sleep(10)
    self:assert_equal(11, reactor.now())
  end)
end

-- Deadlines.

function T:test_deadline_returns_the_results_when_in_time()
  local a, b = support.run_virtual(function()
    return reactor.deadline(5, function(x) reactor.sleep(1); return x, "ok" end, "arg")
  end)
  self:assert_equal("arg", a)
  self:assert_equal("ok", b)
end

function T:test_deadline_raises_and_cancels_when_late()
  local closed = false
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.deadline(2, function()
        local g <close> = setmetatable({}, { __close = function() closed = true end }) -- hecate: test-only
        reactor.sleep(10)
      end)
    end)
  end)
  self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
  self:assert_equal("reactor.deadline: deadline exceeded", err.message) -- coding-standards.md, "Errors"
  self:assert_false(core.is_instance_of(err, core.CancellationError))
  self:assert_true(closed)
end

function T:test_deadline_is_virtual_time_exact()
  support.run_virtual(function()
    local start = reactor.now()
    local ok, err = pcall(reactor.deadline, 2.5, reactor.sleep, 10)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(2.5, reactor.now() - start)
  end)
end

function T:test_deadline_accepts_an_absolute_instant()
  support.run_virtual(function()
    reactor.sleep(4)
    local ok, err = pcall(reactor.deadline, reactor.at(6), reactor.sleep, 10)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(6, reactor.now())
  end)
end

function T:test_deadline_cancels_forked_children()
  support.run_virtual(function()
    local child
    local ok = pcall(reactor.deadline, 1, function()
      child = reactor.fork(function() reactor.sleep(100) end)
      reactor.sleep(50)
    end)
    self:assert_false(ok)
    self:assert_equal("cancelled", child:state())
  end)
end

function T:test_inner_deadline_fires_first_and_is_recoverable()
  support.run_virtual(function()
    local result = reactor.deadline(10, function()
      local ok, err = pcall(reactor.deadline, 1, reactor.sleep, 5)
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
      reactor.sleep(2)
      return "recovered"
    end)
    self:assert_equal("recovered", result)
    self:assert_equal(3, reactor.now())
  end)
end

function T:test_outer_deadline_wins_over_a_longer_inner_one()
  support.run_virtual(function()
    local started = reactor.now()
    local ok, err = pcall(reactor.deadline, 1, function()
      return reactor.deadline(10, reactor.sleep, 5)
    end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(1, reactor.now() - started)
  end)
end

function T:test_deadline_rejects_invalid_arguments()
  support.run_virtual(function()
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.deadline("1", print) end), core.ArgumentError))
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.deadline(1, nil) end), core.ArgumentError))
  end)
end

function T:test_a_finished_deadline_leaves_no_timer_effect()
  support.run_virtual(function()
    reactor.deadline(5, function() return 1 end)
    reactor.sleep(100)
    self:assert_equal(100, reactor.now())
  end)
end

return T
