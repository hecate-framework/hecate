local test = require("harness.test")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local T = test.Case("AsyncSinkTest")

local function run(fn)
  return reactor.Reactor({ clock = "virtual" }):run(fn)
end

local function setup(options)
  local memory = log.MemorySink()
  options = options or {}
  options.sink = options.sink or memory
  local async = log.AsyncSink(options)
  local logger = log.Logger({ sinks = { async }, clock = function() return 0 end })
  return logger, memory, async
end

function T:test_write_does_not_suspend_and_flush_delivers_in_order()
  local logger, memory, async = setup()
  run(function()
    logger:informational("a")
    logger:informational("b")
    self:assert_equal(0, #memory:records())
    self:assert_equal(2, async:pending())
    async:flush()
    self:assert_equal(0, async:pending())
    async:close()
  end)
  local records = memory:records()
  self:assert_equal(2, #records)
  self:assert_equal("a", records[1].message)
  self:assert_equal("b", records[2].message)
end

function T:test_a_full_queue_drops_and_counts()
  local logger, memory, async = setup({ capacity = 2 })
  run(function()
    for _ = 1, 5 do logger:informational("x") end
    async:flush()
    async:close()
  end)
  self:assert_equal(2, #memory:records())
  self:assert_equal(3, async:dropped())
end

function T:test_a_slow_target_does_not_delay_the_caller()
  local written = {}
  local slow = { write = function(_, record) reactor.sleep(10); written[#written + 1] = record.message end }
  local logger, _, async = setup({ sink = slow })
  local elapsed
  run(function()
    local start = reactor.now and reactor.now() or 0
    logger:informational("a")
    logger:informational("b")
    elapsed = (reactor.now and reactor.now() or 0) - start
    async:flush()
    async:close()
  end)
  self:assert_equal(0, elapsed)
  self:assert_equal("a,b", table.concat(written, ","))
end

function T:test_a_raising_target_is_counted_and_does_not_stop_the_drain()
  local calls = 0
  local flaky = { write = function() calls = calls + 1; if calls == 1 then error("boom") end end }
  local logger, _, async = setup({ sink = flaky })
  run(function()
    logger:informational("a")
    logger:informational("b")
    async:flush()
    async:close()
  end)
  self:assert_equal(2, calls)
  self:assert_equal(1, async:failures())
end

function T:test_close_flushes_stops_the_task_and_ignores_later_writes()
  local closed = false
  local memory = log.MemorySink()
  local target = { write = function(_, r) memory:write(r) end, close = function() closed = true end }
  local logger, _, async = setup({ sink = target })
  run(function()
    logger:informational("a")
    async:close()
    logger:informational("late")
    async:close()
  end)
  self:assert_equal(1, #memory:records())
  self:assert_true(closed)
end

function T:test_invalid_options_raise()
  self:assert_error(function() log.AsyncSink({}) end)
  self:assert_error(function() log.AsyncSink({ sink = log.MemorySink(), capacity = 0 }) end)
end

function T:test_flush_after_close_returns_instead_of_waiting_forever()
  local logger, memory, async = setup()
  run(function()
    logger:informational("a")
    async:close()
    async:flush()
  end)
  self:assert_equal(1, #memory:records())
end

return T
