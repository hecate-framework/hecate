---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch  -- the tests pass invalid options and arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
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

function T:test_closing_a_sink_that_was_never_written_needs_no_reactor()
  local closed = 0
  local target = { write = function() end, close = function() closed = closed + 1 end }
  local async = log.AsyncSink({ sink = target })
  async:close()
  async:close() -- idempotent
  self:assert_equal(1, closed)
end

function T:test_closing_a_never_written_sink_whose_target_raises_reports_the_error_to_every_closer()
  local target = { write = function() end, close = function() error(core.Error("target failed"), 0) end }
  local async = log.AsyncSink({ sink = target })
  for _ = 1, 2 do
    local err = self:assert_error(function() async:close() end)
    self:assert_equal("target failed", err.message)
  end
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

function T:test_close_flushes_stops_the_drain_and_ignores_later_writes()
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

function T:test_a_raising_target_close_is_raised_to_every_closer_after_the_drain_ended()
  local memory = log.MemorySink()
  local target = { write = function(_, r) memory:write(r) end, close = function() error("close boom", 0) end }
  local logger, _, async = setup({ sink = target })
  local first_ok, second_ok, second_err
  run(function()
    logger:informational("a")
    first_ok = pcall(async.close, async)
    second_ok, second_err = pcall(async.close, async)
  end)
  self:assert_false(first_ok)
  self:assert_false(second_ok)
  self:assert_equal("close boom", second_err)
  self:assert_equal(1, #memory:records())
end

function T:test_a_second_concurrent_close_waits_for_the_drain_and_reports_the_same_outcome()
  local gate = reactor.Semaphore(0)
  local written, closed = {}, 0
  local target = {
    write = function(_, record) gate:acquire(); written[#written + 1] = record.message end,
    close = function() closed = closed + 1; error("close boom", 0) end,
  }
  local logger, _, async = setup({ sink = target })
  local seen_by_second, results = nil, {}
  run(function()
    logger:informational("a")
    local first = reactor.fork(function() results.first = { pcall(async.close, async) } end)
    local second = reactor.fork(function()
      results.second = { pcall(async.close, async) }
      seen_by_second = #written
    end)
    reactor.sleep(0) -- both closers are now waiting for the drain, which waits for the gate
    self:assert_equal(0, #written)
    self:assert_nil(results.second)
    gate:release()
    reactor.join(first, second)
  end)
  self:assert_equal(1, seen_by_second)
  self:assert_equal(1, closed)
  self:assert_false(results.first[1])
  self:assert_false(results.second[1])
  self:assert_equal("close boom", results.first[2])
  self:assert_equal("close boom", results.second[2])
end

function T:test_a_target_without_close_is_closed_without_error_and_never_written_sink_closes()
  local _, _, never_written = setup()
  local _, _, plain = setup({ sink = { write = function() end } })
  run(function()
    never_written:close()
    plain:close()
  end)
  self:assert_equal(0, never_written:pending())
end

function T:test_the_stop_marker_after_a_raising_write_still_ends_the_drain()
  local failing = { write = function() error("boom") end }
  local logger, _, async = setup({ sink = failing })
  run(function()
    logger:informational("a")
    async:close()
  end)
  self:assert_equal(1, async:failures())
end

return T
