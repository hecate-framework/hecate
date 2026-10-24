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

function T:test_the_ring_keeps_the_newest_records_in_order_over_several_laps()
  local sink = log.MemorySink({ capacity = 3 })
  local logger = log.Logger({ sinks = { sink } })
  local seen = {}
  for i = 1, 8 do
    logger:error("m" .. i)
    local names = {}
    for _, record in ipairs(sink:records()) do names[#names + 1] = record.message end
    seen[#seen + 1] = table.concat(names, ",")
  end
  self:assert_equal("m1", seen[1])
  self:assert_equal("m1,m2,m3", seen[3])
  self:assert_equal("m2,m3,m4", seen[4])
  self:assert_equal("m6,m7,m8", seen[8])
  self:assert_equal(5, sink:dropped())
  sink:clear()
  logger:error("after")
  self:assert_equal("after", sink:records()[1].message)
  self:assert_equal(1, #sink:records())
end

return T
