local test = require("harness.test")
local bench = require("lib.bench")
local T = test.Case("BenchTest")

function T:test_describe_takes_the_first_comment_line()
  self:assert_equal("Micro-benchmark: dispatch.", bench.describe("-- Micro-benchmark: dispatch.\n-- Usage\nlocal x"))
  self:assert_equal("", bench.describe("local x = 1"))
end

function T:test_parse_line_reads_label_value_and_unit()
  local label, value, unit = bench.parse_line("decode records native   312.4 MB/s")
  self:assert_equal("decode records native", label)
  self:assert_equal(312.4, value)
  self:assert_equal("MB/s", unit)
  label, value, unit = bench.parse_line("raw metatable                     0.123 s for 20000000 calls")
  self:assert_equal("raw metatable", label)
  self:assert_equal("s", unit)
  self:assert_nil(bench.parse_line("# backend native is not available: 12 x"))
  self:assert_nil(bench.parse_line("42 s"))
end

function T:test_summarise_groups_by_label_over_runs()
  local rows = bench.summarise({ "a x 10 MB/s\nb y 5 s\n", "a x 30 MB/s\nb y 5 s\n", "a x 20 MB/s\nb y 5 s\n" })
  self:assert_equal(2, #rows)
  self:assert_equal("a x", rows[1].label)
  self:assert_equal(10, rows[1].min)
  self:assert_equal(20, rows[1].median)
  self:assert_equal(30, rows[1].max)
  self:assert_equal(3, rows[1].spread)
  self:assert_equal(1, rows[2].spread)
  self:assert_true(bench.table(rows):find("| a x | MB/s | 3 |", 1, true) ~= nil)
end

function T:test_parse_selection()
  local picked = assert(bench.parse_selection("1, 3-4,3", 5))
  self:assert_equal("1,3,4", table.concat(picked, ","))
  self:assert_equal(5, #assert(bench.parse_selection("a", 5)))
  self:assert_nil(bench.parse_selection("q", 5))
  local none, problem = bench.parse_selection("9", 5)
  self:assert_nil(none)
  self:assert_true(assert(problem):find("9", 1, true) ~= nil)
  self:assert_true(select(2, bench.parse_selection("x", 5)) ~= nil)
end

function T:test_valid_cpu_list()
  self:assert_true(bench.valid_cpu_list("2,3"))
  self:assert_true(bench.valid_cpu_list("2-3,6"))
  self:assert_false(bench.valid_cpu_list("2;ls"))
  self:assert_false(bench.valid_cpu_list(""))
end

return T
