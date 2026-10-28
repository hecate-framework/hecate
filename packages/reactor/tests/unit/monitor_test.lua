local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("MonitorTest")

function T:test_monitor_excludes_and_is_not_reentrant()
  local err
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local permit <close> = monitor:enter()
    self:assert_true(monitor:is_entered())
    err = self:assert_error(function() monitor:enter() end)
  end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_enter_raises_outside_a_managed_coroutine()
  local err = self:assert_error(function() reactor.Monitor():enter() end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

function T:test_wait_notify_hands_the_monitor_over_and_back()
  local log = {}
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local ready = monitor:condition()
    local flag = false
    local waiter = reactor.fork(function()
      local permit <close> = monitor:enter()
      while not flag do ready:wait() end -- leaves the monitor while waiting
      log[#log + 1] = "woke@" .. reactor.now()
    end)
    reactor.sleep(2)
    do
      local permit <close> = monitor:enter() -- possible: the waiter left the monitor
      flag = true
      ready:notify()
      log[#log + 1] = "notified"
    end
    waiter:value()
  end)
  self:assert_equal("notified,woke@2", table.concat(log, ","))
end

function T:test_notify_wakes_one_waiter_in_arrival_order_and_broadcast_wakes_all()
  local log = {}
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local tokens = 0
    for _, name in ipairs({ "a", "b", "c" }) do
      reactor.fork(function()
        local permit <close> = monitor:enter()
        while tokens == 0 do condition:wait() end
        tokens = tokens - 1
        log[#log + 1] = name
      end)
      reactor.sleep(0)
    end
    self:assert_equal(3, condition:waiting())
    do
      local permit <close> = monitor:enter()
      tokens = 1
      condition:notify()
    end
    reactor.sleep(1)
    self:assert_equal("a", table.concat(log, ","))
    do
      local permit <close> = monitor:enter()
      tokens = 2
      condition:broadcast()
    end
  end)
  self:assert_equal("a,b,c", table.concat(log, ","))
end

function T:test_notify_without_waiters_is_lost()
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local permit <close> = monitor:enter()
    condition:notify()
    condition:broadcast()
    self:assert_equal(0, condition:waiting())
  end)
end

function T:test_wait_notify_and_broadcast_require_the_monitor()
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    for _, operation in ipairs({
      function() condition:wait() end,
      function() condition:notify() end,
      function() condition:broadcast() end,
    }) do
      local err = self:assert_error(operation)
      self:assert_true(core.is_instance_of(err, core.ArgumentError))
    end
    local other = reactor.fork(function()
      local permit <close> = monitor:enter()
      reactor.sleep(1)
    end)
    reactor.sleep(0)
    local err = self:assert_error(function() condition:notify() end) -- occupied by another coroutine
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
    other:value()
  end)
end

function T:test_condition_requires_a_monitor()
  local err = self:assert_error(function() reactor.Condition({}) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_cancelled_wait_reenters_the_monitor_before_raising()
  local inside_at_cleanup, entered_by_other, state
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local waiter = reactor.fork(function()
      local permit <close> = monitor:enter()
      local guard <close> = setmetatable({}, { -- hecate: test-only
        __close = function() inside_at_cleanup = monitor:is_entered() end,
      })
      condition:wait()
    end)
    reactor.sleep(0)
    -- Another coroutine holds the monitor when the cancellation arrives: the cancelled
    -- waiter must queue for it, uncancellably, instead of running its cleanup outside.
    local holder = reactor.fork(function()
      local permit <close> = monitor:enter()
      waiter:cancel()
      reactor.sleep(3)
      entered_by_other = reactor.now()
    end)
    reactor.sleep(1)
    self:assert_false(waiter:done())
    holder:value()
    reactor.sleep(0)
    state = waiter:state()
    self:assert_false(monitor:is_entered())
  end)
  self:assert_equal("cancelled", state)
  self:assert_true(inside_at_cleanup)
  self:assert_equal(3, entered_by_other)
end

function T:test_cancelled_waiter_does_not_swallow_a_notification()
  local woken
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local condition = monitor:condition()
    local first = reactor.fork(function()
      local permit <close> = monitor:enter()
      condition:wait()
    end)
    reactor.sleep(0)
    local second = reactor.fork(function()
      local permit <close> = monitor:enter()
      condition:wait()
      woken = true
    end)
    reactor.sleep(0)
    first:cancel()
    do
      local permit <close> = monitor:enter()
      condition:notify() -- first in the queue is cancelled: the notification must reach the second
    end
    second:value()
  end)
  self:assert_true(woken)
end

function T:test_a_waiter_nobody_notifies_is_a_deadlock()
  local err = self:assert_error(function()
    support.run_virtual(function()
      local monitor = reactor.Monitor()
      local permit <close> = monitor:enter()
      monitor:condition():wait()
    end)
  end)
  self:assert_true(err.message:find("deadlock") ~= nil)
end

function T:test_bounded_buffer_built_from_a_monitor()
  local consumed = {}
  support.run_virtual(function()
    local monitor = reactor.Monitor()
    local not_full, not_empty = monitor:condition(), monitor:condition()
    local items, limit = {}, 2
    reactor.scope(function(scope)
      scope:fork(function()
        for i = 1, 6 do
          local permit <close> = monitor:enter()
          while #items == limit do not_full:wait() end
          items[#items + 1] = i
          not_empty:notify()
        end
      end)
      scope:fork(function()
        for _ = 1, 6 do
          local permit <close> = monitor:enter()
          while #items == 0 do not_empty:wait() end
          consumed[#consumed + 1] = table.remove(items, 1)
          not_full:notify()
        end
      end)
    end)
  end)
  self:assert_equal("1,2,3,4,5,6", table.concat(consumed, ","))
end

return T
