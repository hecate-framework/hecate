local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("SemaphoreTest")

function T:test_units_must_be_a_non_negative_integer()
  for _, bad in ipairs({ -1, 0.5, "1" }) do
    local err = self:assert_error(function() reactor.Semaphore(bad) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end
end

function T:test_acquire_raises_outside_a_managed_coroutine()
  local err = self:assert_error(function() reactor.Semaphore(1):acquire() end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
  err = self:assert_error(function() reactor.Mutex():lock() end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

function T:test_at_most_n_coroutines_hold_the_semaphore()
  local peak, current = 0, 0
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(2)
    for _ = 1, 6 do
      reactor.fork(function()
        local permit <close> = semaphore:acquire()
        current = current + 1
        peak = math.max(peak, current)
        reactor.sleep(1)
        current = current - 1
      end)
    end
  end)
  self:assert_equal(2, peak)
end

function T:test_waiters_are_served_in_arrival_order_without_barging()
  local order = {}
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    local holder = semaphore:acquire()
    for _, name in ipairs({ "a", "b", "c" }) do
      reactor.fork(function()
        local permit <close> = semaphore:acquire()
        order[#order + 1] = name
        reactor.sleep(1)
      end)
      reactor.sleep(0)
    end
    holder:release()
    -- a newcomer arriving at the moment of the release must queue behind the waiters
    reactor.fork(function()
      local permit <close> = semaphore:acquire()
      order[#order + 1] = "late"
    end)
  end)
  self:assert_equal("a,b,c,late", table.concat(order, ","))
end

function T:test_permit_released_by_close_even_when_the_body_fails()
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    pcall(function()
      local permit <close> = semaphore:acquire()
      error("boom", 0)
    end)
    self:assert_equal(1, semaphore:available())
  end)
end

function T:test_permit_release_is_idempotent()
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    local permit = semaphore:acquire()
    self:assert_true(permit:is_held())
    permit:release()
    permit:release()
    self:assert_false(permit:is_held())
    self:assert_equal(1, semaphore:available())
  end)
end

function T:test_try_acquire_never_suspends()
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    local permit = semaphore:try_acquire()
    self:assert_not_nil(permit)
    self:assert_nil(semaphore:try_acquire())
    permit:release()
    self:assert_not_nil(semaphore:try_acquire())
  end)
end

function T:test_release_adds_a_unit_for_signalling_without_a_permit()
  local got
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(0)
    local consumer = reactor.fork(function() semaphore:acquire(); got = reactor.now() end)
    reactor.sleep(4)
    semaphore:release()
    consumer:value()
  end)
  self:assert_equal(4, got)
end

function T:test_cancelled_waiter_is_withdrawn_and_loses_no_permit()
  local second_got_it, state
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    local holder = semaphore:acquire()
    local first = reactor.fork(function() semaphore:acquire() end)
    reactor.fork(function()
      local permit <close> = semaphore:acquire()
      second_got_it = true
    end)
    reactor.sleep(0)
    self:assert_equal(2, semaphore:waiting())
    first:cancel()
    holder:release() -- the cancelled waiter is first in line: its unit must go to the next one
    reactor.sleep(0)
    state = first:state()
    self:assert_equal(1, semaphore:available())
    self:assert_equal(0, semaphore:waiting())
  end)
  self:assert_true(second_got_it)
  self:assert_equal("cancelled", state)
end

function T:test_cancelled_scope_releases_what_its_children_held()
  support.run_virtual(function()
    local semaphore = reactor.Semaphore(1)
    pcall(reactor.deadline, 1, function()
      reactor.fork(function()
        local permit <close> = semaphore:acquire()
        reactor.sleep(10)
      end)
      reactor.sleep(10)
    end)
    self:assert_equal(1, semaphore:available())
  end)
end

function T:test_unreleased_semaphore_is_a_deadlock()
  local err = self:assert_error(function()
    support.run_virtual(function()
      local semaphore = reactor.Semaphore(1)
      local _permit <close> = semaphore:acquire()
      semaphore:acquire()
    end)
  end)
  self:assert_true(err.message:find("deadlock") ~= nil)
end

-- Mutex

function T:test_mutex_excludes_and_is_fifo()
  local log = {}
  support.run_virtual(function()
    local mutex = reactor.Mutex()
    for _, name in ipairs({ "a", "b", "c" }) do
      reactor.fork(function()
        local permit <close> = mutex:lock()
        log[#log + 1] = name .. "+"
        reactor.sleep(1) -- a suspension inside the critical section
        log[#log + 1] = name .. "-"
      end)
    end
  end)
  self:assert_equal("a+,a-,b+,b-,c+,c-", table.concat(log, ","))
end

function T:test_mutex_try_lock_and_state()
  support.run_virtual(function()
    local mutex = reactor.Mutex()
    self:assert_false(mutex:is_locked())
    local permit = mutex:try_lock()
    self:assert_true(mutex:is_locked())
    self:assert_nil(mutex:try_lock())
    permit:release()
    self:assert_false(mutex:is_locked())
  end)
end

function T:test_mutex_waiter_cancelled_by_a_deadline_leaves_the_mutex_usable()
  local locked_again
  support.run_virtual(function()
    local mutex = reactor.Mutex()
    local holder = mutex:lock()
    local err = self:assert_error(function() reactor.deadline(1, function() mutex:lock() end) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    holder:release()
    locked_again = mutex:try_lock() ~= nil
  end)
  self:assert_true(locked_again)
end

return T
