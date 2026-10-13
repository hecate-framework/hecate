local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local function run(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end
local T = test.Case("SyncTest")

-- Channel.

function T:test_buffered_channel_preserves_order_without_suspending()
  run(function()
    local ch = reactor.Channel(3)
    ch:send(1); ch:send(2); ch:send(3)
    self:assert_equal(3, ch:length())
    self:assert_equal(1, ch:receive())
    self:assert_equal(2, ch:receive())
    self:assert_equal(3, ch:receive())
  end)
end

function T:test_rendezvous_send_waits_for_the_receiver()
  local log = {}
  run(function()
    local ch = reactor.Channel()
    reactor.fork(function() ch:send("v"); log[#log + 1] = "sent@" .. reactor.now() end)
    reactor.sleep(5)
    log[#log + 1] = "recv:" .. ch:receive()
    reactor.sleep(0)
  end)
  self:assert_equal("recv:v,sent@5", table.concat(log, ","))
end

function T:test_full_channel_blocks_sender_until_room()
  local log = {}
  run(function()
    local ch = reactor.Channel(1)
    ch:send("a")
    reactor.fork(function() ch:send("b"); log[#log + 1] = "b sent" end)
    reactor.sleep(1)
    self:assert_equal(0, #log)
    self:assert_equal("a", ch:receive())
    self:assert_equal("b", ch:receive())
    reactor.sleep(0)
  end)
  self:assert_equal(1, #log)
end

function T:test_receive_waits_and_wakes_in_fifo_order()
  local got = {}
  run(function()
    local ch = reactor.Channel()
    for i = 1, 3 do reactor.fork(function() got[i] = ch:receive() end) end
    reactor.sleep(1)
    ch:send("x"); ch:send("y"); ch:send("z")
  end)
  self:assert_equal("x,y,z", table.concat(got, ","))
end

function T:test_close_drains_then_returns_nil_and_rejects_sends()
  run(function()
    local ch = reactor.Channel(2)
    ch:send(1)
    ch:close()
    ch:close()
    self:assert_true(ch:is_closed())
    self:assert_equal(1, ch:receive())
    self:assert_equal(nil, ch:receive())
    local err = self:assert_error(function() ch:send(2) end)
    self:assert_equal("hecate.reactor.ChannelClosed", err.code)
  end)
end

function T:test_close_wakes_blocked_receivers_and_senders()
  run(function()
    local rx = reactor.Channel()
    local tx = reactor.Channel()
    local receiver = reactor.fork(function() return rx:receive() end)
    local sender = reactor.fork(function() return select(2, pcall(tx.send, tx, 1)) end)
    reactor.sleep(1)
    rx:close(); tx:close()
    self:assert_equal(nil, receiver:value())
    self:assert_equal("hecate.reactor.ChannelClosed", sender:value().code)
  end)
end

function T:test_nil_and_invalid_capacity_are_rejected()
  run(function()
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.Channel(1):send(nil) end), core.ArgumentError))
    ---@diagnostic disable-next-line: param-type-mismatch  -- intentionally invalid
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.Channel(-1) end), core.ArgumentError))
  end)
end

function T:test_cancelled_receiver_does_not_consume_a_value()
  run(function()
    local ch = reactor.Channel()
    local rx = reactor.fork(function() return ch:receive() end)
    reactor.sleep(1)
    rx:cancel()
    reactor.sleep(1)
    self:assert_equal("cancelled", rx:state())
    local second = reactor.fork(function() return ch:receive() end)
    reactor.sleep(1)
    ch:send("kept")
    self:assert_equal("kept", second:value())
  end)
end

function T:test_receive_future_works_in_select()
  run(function()
    local a, b = reactor.Channel(), reactor.Channel()
    reactor.fork(function() reactor.sleep(2); b:send("from b") end)
    local index, value = reactor.select(a:receive_future(), b:receive_future())
    self:assert_equal(2, index)
    self:assert_equal("from b", value)
  end)
end

-- Semaphore and Mutex.

function T:test_semaphore_limits_concurrency()
  local running, peak = 0, 0
  run(function()
    local sem = reactor.Semaphore(2)
    for _ = 1, 5 do
      reactor.fork(function()
        local permit <close> = sem:acquire()
        running = running + 1
        peak = math.max(peak, running)
        reactor.sleep(1)
        running = running - 1
      end)
    end
  end)
  self:assert_equal(2, peak)
end

function T:test_semaphore_hands_permits_over_in_fifo_order()
  local order = {}
  run(function()
    local sem = reactor.Semaphore(1)
    local held = sem:acquire()
    for i = 1, 3 do
      reactor.fork(function()
        local p <close> = sem:acquire()
        order[#order + 1] = i
      end)
    end
    reactor.sleep(1)
    held:release()
    held:release() -- releasing twice returns a single permit
  end)
  self:assert_equal("1,2,3", table.concat(order, ","))
end

function T:test_try_acquire_never_suspends()
  run(function()
    local sem = reactor.Semaphore(1)
    local p = sem:try_acquire()
    self:assert_true(p ~= nil)
    self:assert_equal(nil, sem:try_acquire())
    p:release()
    self:assert_equal(1, sem:available())
  end)
end

function T:test_cancelled_waiter_leaves_the_permit_available()
  run(function()
    local sem = reactor.Semaphore(1)
    local held = sem:acquire()
    local waiter = reactor.fork(function() sem:acquire() end)
    reactor.sleep(1)
    waiter:cancel()
    reactor.sleep(1)
    held:release()
    self:assert_equal(1, sem:available())
  end)
end

function T:test_mutex_serialises_a_read_modify_write_across_suspension()
  local counter = 0
  run(function()
    local mutex = reactor.Mutex()
    for _ = 1, 10 do
      reactor.fork(function()
        local lock <close> = mutex:lock()
        local seen = counter
        reactor.sleep(1)
        counter = seen + 1
      end)
    end
  end)
  self:assert_equal(10, counter)
end

function T:test_mutex_permit_is_released_when_the_holder_is_cancelled()
  run(function()
    local mutex = reactor.Mutex()
    local holder = reactor.fork(function()
      local lock <close> = mutex:lock()
      reactor.sleep(100)
    end)
    reactor.sleep(1)
    self:assert_true(mutex:is_locked())
    holder:cancel()
    reactor.sleep(1)
    self:assert_false(mutex:is_locked())
  end)
end

-- Monitor and Condition.

function T:test_condition_wait_and_signal()
  local log = {}
  run(function()
    local monitor = reactor.Monitor()
    local ready = monitor:condition()
    local flag = false
    reactor.fork(function()
      local m <close> = monitor:enter()
      while not flag do ready:wait() end
      log[#log + 1] = "woken@" .. reactor.now()
    end)
    reactor.sleep(3)
    do
      local m <close> = monitor:enter()
      flag = true
      ready:signal()
    end
    reactor.sleep(0)
  end)
  self:assert_equal("woken@3", log[1])
end

function T:test_broadcast_wakes_every_waiter_one_at_a_time_inside_the_monitor()
  local inside, peak, woken = 0, 0, 0
  run(function()
    local monitor = reactor.Monitor()
    local cond = reactor.Condition(monitor)
    local go = false
    for _ = 1, 3 do
      reactor.fork(function()
        local m <close> = monitor:enter()
        while not go do cond:wait() end
        inside = inside + 1
        peak = math.max(peak, inside)
        reactor.sleep(1)
        inside = inside - 1
        woken = woken + 1
      end)
    end
    reactor.sleep(1)
    local m <close> = monitor:enter()
    go = true
    cond:broadcast()
  end)
  self:assert_equal(3, woken)
  self:assert_equal(1, peak)
end

function T:test_wait_outside_the_monitor_raises()
  run(function()
    local monitor = reactor.Monitor()
    local err = self:assert_error(function() monitor:condition():wait() end)
    self:assert_true(core.is_instance_of(err, core.Error))
  end)
end

function T:test_cancelled_wait_reenters_the_monitor_before_raising()
  local inside_on_cancel
  run(function()
    local monitor = reactor.Monitor()
    local cond = monitor:condition()
    local f = reactor.fork(function()
      local m <close> = monitor:enter()
      local ok = pcall(cond.wait, cond)
      inside_on_cancel = (not ok) and monitor:is_inside()
    end)
    reactor.sleep(1)
    f:cancel()
    reactor.sleep(1)
    self:assert_false(monitor:is_inside())
    local m <close> = monitor:enter() -- the cancelled waiter left the monitor properly
  end)
  self:assert_true(inside_on_cancel)
end

function T:test_blocking_primitives_need_a_managed_coroutine()
  local err = self:assert_error(function() reactor.Mutex():lock() end)
  self:assert_true(core.is_instance_of(err, core.Error))
  local err2 = self:assert_error(function() reactor.Channel():receive() end)
  self:assert_true(core.is_instance_of(err2, core.NonYieldableContextError))
end

return T
