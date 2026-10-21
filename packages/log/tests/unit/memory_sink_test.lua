local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("MemorySinkTest")

function T:test_records_are_kept_in_order()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink } })
  logger:error("a")
  logger:error("b")
  self:assert_equal("a", sink:records()[1].message)
  self:assert_equal("b", sink:records()[2].message)
end

function T:test_records_returns_a_copy_and_clear_empties_the_sink()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink } })
  logger:error("a")
  sink:records()[1] = nil
  self:assert_equal(1, #sink:records())
  sink:clear()
  self:assert_equal(0, #sink:records())
end

function T:test_a_capacity_drops_the_oldest_records_and_counts_them()
  local sink = log.MemorySink({ capacity = 2 })
  local logger = log.Logger({ sinks = { sink } })
  for _, name in ipairs({ "a", "b", "c" }) do logger:error(name) end
  self:assert_equal(2, #sink:records())
  self:assert_equal("b", sink:records()[1].message)
  self:assert_equal(1, sink:dropped())
end

function T:test_an_invalid_capacity_is_rejected()
  self:assert_error(function() log.MemorySink({ capacity = 0 }) end)
end

return T
