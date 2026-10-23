local test = require("harness.test")
local stats = dofile("benchmarks/lib/stats.lua")
local T = test.Case("BenchmarkStatsTest")

function T:test_percentile_uses_the_nearest_rank()
  local values = {}
  for i = 1, 1000 do values[i] = i end
  self:assert_equal(500, stats.percentile(values, 50))
  self:assert_equal(990, stats.percentile(values, 99))
  self:assert_equal(999, stats.percentile(values, 99.9))
  self:assert_equal(1, stats.percentile(values, 0.01))
  self:assert_equal(7, stats.percentile({ 7 }, 99))
end

function T:test_median_does_not_reorder_its_input()
  local values = { 3, 1, 2, 10 }
  self:assert_equal(2.5, stats.median(values))
  self:assert_equal(3, values[1])
end

function T:test_mann_whitney_separates_disjoint_samples()
  local u, p = stats.mann_whitney({ 1, 2, 3, 4, 5, 6, 7, 8 }, { 11, 12, 13, 14, 15, 16, 17, 18 })
  self:assert_equal(0, u)
  self:assert_true(p < 0.01, "p = " .. p)
end

function T:test_mann_whitney_accepts_identical_samples()
  local _, p = stats.mann_whitney({ 5, 5, 5, 5 }, { 5, 5, 5, 5 })
  self:assert_equal(1, p)
  _, p = stats.mann_whitney({ 1, 4, 5, 8, 9 }, { 2, 3, 6, 7, 10 })
  self:assert_true(p > 0.5, "p = " .. p)
end

return T
