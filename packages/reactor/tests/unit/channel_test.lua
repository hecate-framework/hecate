local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("ChannelTest")

function T:test_capacity_must_be_a_non_negative_integer()
  for _, bad in ipairs({ -1, 1.5, "2" }) do
    local err = self:assert_error(function() reactor.Channel(bad) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end
  self:assert_equal(0, reactor.Channel():capacity())
  self:assert_equal(3, reactor.Channel(3):capacity())
end

function T:test_suspending_operations_raise_outside_a_managed_coroutine()
  local channel = reactor.Channel()
  for _, operation in ipairs({
    function() channel:send(1) end,
    function() channel:receive() end,
  }) do
    local err = self:assert_error(operation)
    self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
  end
end

function T:test_rendezvous_sender_waits_for_the_receiver()
  local log = {}
  support.run_virtual(function()
    local channel = reactor.Channel(0)
    reactor.fork(function()
      channel:send("v")
      log[#log + 1] = "sent@" .. reactor.now()
    end)
    reactor.sleep(2)
    log[#log + 1] = "receiving"
    log[#log + 1] = channel:receive()
  end)
  self:assert_equal("receiving,v,sent@2", table.concat(log, ","))
end

function T:test_rendezvous_receiver_waits_for_the_sender()
  local got, at
  support.run_virtual(function()
    local channel = reactor.Channel(0)
    local receiver = reactor.fork(function() got = channel:receive(); at = reactor.now() end)
    reactor.sleep(3)
    channel:send("late")
    receiver:value()
  end)
  self:assert_equal("late", got)
  self:assert_equal(3, at)
end

function T:test_buffered_channel_is_fifo_and_blocks_when_full()
  local log = {}
  support.run_virtual(function()
    local channel = reactor.Channel(2)
    reactor.fork(function()
      for i = 1, 4 do
        channel:send(i)
        log[#log + 1] = "sent" .. i
      end
    end)
    reactor.sleep(1)
    self:assert_equal(2, channel:length())
    for _ = 1, 4 do
      local value = channel:receive()
      log[#log + 1] = "got" .. value
    end
  end)
  -- Taking a value moves the blocked sender's value into the buffer at once; the sender
  -- itself only runs when the main coroutine suspends on the empty channel.
  self:assert_equal("sent1,sent2,got1,got2,got3,sent3,sent4,got4", table.concat(log, ","))
end

function T:test_nil_is_a_valid_value()
  local ok, value
  support.run_virtual(function()
    local channel = reactor.Channel(1)
    channel:send(nil)
    ok, value = pcall(channel.receive, channel)
  end)
  self:assert_true(ok)
  self:assert_nil(value)
end

function T:test_receivers_are_served_in_arrival_order()
  local log = {}
  support.run_virtual(function()
    local channel = reactor.Channel()
    for _, name in ipairs({ "a", "b", "c" }) do
      reactor.fork(function()
        local value = channel:receive()
        log[#log + 1] = name .. "=" .. value
      end)
      reactor.sleep(0)
    end
    for i = 1, 3 do channel:send(i) end
  end)
  self:assert_equal("a=1,b=2,c=3", table.concat(log, ","))
end

function T:test_senders_are_served_in_arrival_order()
  local got = {}
  support.run_virtual(function()
    local channel = reactor.Channel()
    for _, name in ipairs({ "a", "b", "c" }) do
      reactor.fork(function() channel:send(name) end)
      reactor.sleep(0)
    end
    for _ = 1, 3 do got[#got + 1] = channel:receive() end
  end)
  self:assert_equal("a,b,c", table.concat(got, ","))
end

function T:test_cancelled_receiver_does_not_lose_a_value()
  local first_state, second
  support.run_virtual(function()
    local channel = reactor.Channel()
    local first = reactor.fork(function() return channel:receive() end)
    local other = reactor.fork(function() second = channel:receive() end)
    reactor.sleep(0)
    first:cancel()
    channel:send("kept") -- the cancelled receiver is first in the queue but must be skipped
    other:value()
    first_state = first:state()
  end)
  self:assert_equal("cancelled", first_state)
  self:assert_equal("kept", second)
end

function T:test_cancelled_sender_does_not_deliver_its_value()
  local got
  support.run_virtual(function()
    local channel = reactor.Channel()
    local first = reactor.fork(function() channel:send("cancelled") end)
    reactor.fork(function() channel:send("delivered") end)
    reactor.sleep(0)
    first:cancel()
    got = channel:receive()
  end)
  self:assert_equal("delivered", got)
end

function T:test_cancelled_sender_on_a_full_buffer_leaves_the_buffer_intact()
  local got = {}
  support.run_virtual(function()
    local channel = reactor.Channel(1)
    channel:send("a")
    local blocked = reactor.fork(function() channel:send("b") end)
    reactor.sleep(0)
    blocked:cancel()
    reactor.sleep(0)
    got[1] = channel:receive()
    self:assert_equal(0, channel:length())
  end)
  self:assert_equal("a", got[1])
end

function T:test_cancellation_runs_close_handlers_of_a_waiting_receiver()
  local closed = false
  support.run_virtual(function()
    local channel = reactor.Channel()
    local child = reactor.fork(function()
      local guard <close> = setmetatable({}, { __close = function() closed = true end }) -- hecate: test-only
      channel:receive()
    end)
    reactor.sleep(0)
    child:cancel()
    reactor.sleep(0)
  end)
  self:assert_true(closed)
end

function T:test_close_lets_receivers_drain_then_raises()
  local values, err
  support.run_virtual(function()
    local channel = reactor.Channel(3)
    channel:send(1)
    channel:send(2)
    self:assert_true(channel:close())
    self:assert_false(channel:close()) -- idempotent
    self:assert_true(channel:is_closed())
    values = { channel:receive(), channel:receive() }
    err = self:assert_error(function() channel:receive() end)
  end)
  self:assert_equal("1,2", table.concat(values, ","))
  self:assert_true(core.is_instance_of(err, core.ClosedChannelError))
end

function T:test_send_on_a_closed_channel_raises()
  local err
  support.run_virtual(function()
    local channel = reactor.Channel(5)
    channel:close()
    err = self:assert_error(function() channel:send(1) end)
  end)
  self:assert_true(core.is_instance_of(err, core.ClosedChannelError))
end

function T:test_close_wakes_every_waiting_receiver_and_sender()
  local outcomes = {}
  support.run_virtual(function()
    local empty, full = reactor.Channel(), reactor.Channel()
    for i = 1, 2 do
      reactor.fork(function()
        local ok, err = pcall(empty.receive, empty)
        outcomes["r" .. i] = not ok and core.is_instance_of(err, core.ClosedChannelError)
      end)
      reactor.fork(function()
        local ok, err = pcall(full.send, full, i)
        outcomes["s" .. i] = not ok and core.is_instance_of(err, core.ClosedChannelError)
      end)
    end
    reactor.sleep(1)
    empty:close()
    full:close()
  end)
  self:assert_true(outcomes.r1 and outcomes.r2 and outcomes.s1 and outcomes.s2)
end

function T:test_blocked_receive_with_no_possible_sender_is_a_deadlock()
  local err = self:assert_error(function()
    support.run_virtual(function() reactor.Channel():receive() end)
  end)
  self:assert_true(err.message:find("deadlock") ~= nil)
end

function T:test_blocked_send_on_a_rendezvous_channel_is_a_deadlock()
  local err = self:assert_error(function()
    support.run_virtual(function() reactor.Channel(0):send(1) end)
  end)
  self:assert_true(err.message:find("deadlock") ~= nil)
end

-- select

function T:test_select_receives_from_a_ready_channel()
  local index, value
  support.run_virtual(function()
    local channel = reactor.Channel(1)
    channel:send("x")
    index, value = reactor.select(channel:receive_op())
  end)
  self:assert_equal(1, index)
  self:assert_equal("x", value)
end

function T:test_select_prefers_the_first_ready_item_and_the_loser_keeps_its_value()
  local index, value, kept
  support.run_virtual(function()
    local a, b = reactor.Channel(1), reactor.Channel(1)
    a:send("from a")
    b:send("from b")
    index, value = reactor.select(a:receive_op(), b:receive_op())
    kept = b:receive()
  end)
  self:assert_equal(1, index)
  self:assert_equal("from a", value)
  self:assert_equal("from b", kept)
end

function T:test_select_waits_for_the_first_channel_to_receive()
  local index, value, at
  support.run_virtual(function()
    local a, b = reactor.Channel(), reactor.Channel()
    reactor.fork(function() reactor.sleep(5); a:send("slow") end)
    reactor.fork(function() reactor.sleep(2); b:send("fast") end)
    index, value = reactor.select(a:receive_op(), b:receive_op())
    at = reactor.now()
    self:assert_equal("slow", a:receive()) -- the other sender was not consumed by select
  end)
  self:assert_equal(2, index)
  self:assert_equal("fast", value)
  self:assert_equal(2, at)
end

function T:test_select_send_operation_completes_when_a_receiver_arrives()
  local index, value, received
  support.run_virtual(function()
    local channel = reactor.Channel()
    reactor.fork(function() reactor.sleep(1); received = channel:receive() end)
    index, value = reactor.select(channel:send_op("payload"))
  end)
  self:assert_equal(1, index)
  self:assert_nil(value)
  self:assert_equal("payload", received)
end

function T:test_select_send_operation_on_a_buffered_channel_is_immediate()
  local index, length
  support.run_virtual(function()
    local channel = reactor.Channel(1)
    index = reactor.select(channel:send_op(1))
    length = channel:length()
  end)
  self:assert_equal(1, index)
  self:assert_equal(1, length)
end

function T:test_select_mixes_futures_and_channel_operations()
  local results = {}
  support.run_virtual(function()
    local channel = reactor.Channel()
    local timer = reactor.fork(function() reactor.sleep(1); return "timer" end)
    results[1], results[2] = reactor.select(channel:receive_op(), timer)
    local slow = reactor.fork(function() reactor.sleep(100) end)
    reactor.fork(function() reactor.sleep(1); channel:send("message") end)
    results[3], results[4] = reactor.select(slow, channel:receive_op())
    reactor.sleep(0)
    results[5] = slow:state()
  end)
  self:assert_equal(2, results[1])
  self:assert_equal("timer", results[2])
  self:assert_equal(2, results[3])
  self:assert_equal("message", results[4])
  self:assert_equal("cancelled", results[5]) -- select cancels the futures it did not pick
end

function T:test_cancelled_select_withdraws_its_waiters_so_no_value_is_lost()
  local got
  support.run_virtual(function()
    local channel = reactor.Channel()
    local selecting = reactor.fork(function() reactor.select(channel:receive_op()) end)
    reactor.sleep(0)
    selecting:cancel()
    reactor.sleep(0)
    reactor.fork(function() channel:send("kept") end)
    got = channel:receive()
  end)
  self:assert_equal("kept", got)
end

function T:test_a_hand_off_to_a_select_is_not_duplicated_across_its_channels()
  local log = {}
  support.run_virtual(function()
    local a, b = reactor.Channel(), reactor.Channel()
    reactor.fork(function() log[#log + 1] = select(2, reactor.select(a:receive_op(), b:receive_op())) end)
    reactor.sleep(0)
    a:send(1)
    reactor.sleep(0)
    -- the select is over and withdrew its receiver from b
    self:assert_equal(0, b._receivers.size)
    b:close()
  end)
  self:assert_equal("1", table.concat(log, ","))
end

function T:test_select_raises_when_a_channel_is_closed()
  local err_ready, err_waiting
  support.run_virtual(function()
    local closed = reactor.Channel()
    closed:close()
    err_ready = self:assert_error(function() reactor.select(closed:receive_op()) end)
    local channel = reactor.Channel()
    reactor.fork(function() reactor.sleep(1); channel:close() end)
    err_waiting = self:assert_error(function() reactor.select(channel:receive_op()) end)
  end)
  self:assert_true(core.is_instance_of(err_ready, core.ClosedChannelError))
  self:assert_true(core.is_instance_of(err_waiting, core.ClosedChannelError))
end

function T:test_select_rejects_other_values()
  support.run_virtual(function()
    local err = self:assert_error(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      reactor.select(reactor.Channel())
    end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_select_over_channels_that_nobody_serves_is_a_deadlock()
  local err = self:assert_error(function()
    support.run_virtual(function()
      reactor.select(reactor.Channel():receive_op(), reactor.Channel():receive_op())
    end)
  end)
  self:assert_true(err.message:find("deadlock") ~= nil)
end

return T
