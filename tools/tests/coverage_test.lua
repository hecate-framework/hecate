local test = require("harness.test")
local coverage = require("lib.coverage")
local T = test.Case("CoverageTest")

function T:test_executable_lines_skip_blanks_comments_and_delimiters()
  local lines = coverage.executable_lines("-- header\nlocal x = 1\n\nif x then\n  return x\nend\n--[[ long\nlocal y\n]]\nreturn 2\n")
  self:assert_true(lines[2])
  self:assert_true(lines[4])
  self:assert_true(lines[5])
  self:assert_true(lines[10])
  self:assert_nil(lines[1])
  self:assert_nil(lines[3])
  self:assert_nil(lines[6])
  self:assert_nil(lines[8])
end

function T:test_parse_hits_merges_records()
  local hits = coverage.parse_hits("a.lua\t1\na.lua\t3\nb.lua\t2\n")
  coverage.parse_hits("a.lua\t4\n", hits)
  self:assert_true(hits["a.lua"][1] and hits["a.lua"][3] and hits["a.lua"][4])
  self:assert_true(hits["b.lua"][2])
end

function T:test_count_ignores_hits_outside_executable_lines()
  local total, covered = coverage.count({ [1] = true, [2] = true }, { [2] = true, [9] = true })
  self:assert_equal(2, total)
  self:assert_equal(1, covered)
end

function T:test_normalize_collapses_parent_segments()
  self:assert_equal("packages/core/src/a.lua", coverage.normalize("tools/../packages\\core/src/a.lua"))
  self:assert_equal("../x.lua", coverage.normalize("../x.lua"))
end

function T:test_percent_of_an_empty_file_is_full()
  self:assert_equal(100, coverage.percent(0, 0))
  self:assert_equal(50, coverage.percent(4, 2))
end

function T:test_lcov_lists_hits_per_line()
  local text = coverage.lcov({ { path = "b.lua", executable = { [1] = true }, hit = nil },
    { path = "a.lua", executable = { [1] = true, [2] = true }, hit = { [2] = true } } })
  self:assert_equal("SF:a.lua\nDA:1,0\nDA:2,1\nLF:2\nLH:1\nend_of_record\n"
    .. "SF:b.lua\nDA:1,0\nLF:1\nLH:0\nend_of_record\n", text)
end

function T:test_check_flags_packages_under_threshold()
  local problems = coverage.check({ core = { total = 100, covered = 95 }, reactor = { total = 100, covered = 80 },
    http = { total = 10, covered = 0 } })
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("reactor", 1, true) ~= nil)
end

function T:test_environment_sets_the_directory_per_platform()
  self:assert_equal("HECATE_TEST_COVERAGE='d' ", coverage.environment("d", false))
  self:assert_equal("set HECATE_TEST_COVERAGE=d&& ", coverage.environment("d", true))
end

return T
