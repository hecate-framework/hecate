local hecate_test = require("hecate.test")
local T = hecate_test.Case("ReportersTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local fixtures = here .. "/../fixtures"

local function read(name)
  local f = assert(io.open(fixtures .. "/" .. name, "rb"))
  local text = f:read("a")
  f:close()
  return (text:gsub("\r\n", "\n"))
end

-- A run built by hand: deterministic, no locations that depend on the lines of this file.
-- Three suites: all passing, one failing and one erroring among four, and one whose tests are
-- all fast and passing.
local function sample()
  local function passed(name, assertions)
    return { name = name, case = "C", status = "passed", assertions = assertions, duration = 0 }
  end
  return {
    { name = "tests/unit/alpha_test.lua", tests = {
      passed("Alpha.test_a", 2), passed("Alpha.test_b", 1), passed("Alpha.test_c", 3) } },
    { name = "tests/unit/beta_test.lua", tests = {
      passed("Beta.test_a", 1),
      { name = "Beta.test_b_fails", case = "Beta", status = "failed", assertions = 2, duration = 0,
        location = "tests/unit/beta_test.lua:12", message = "tables differ:\n  .b[1]: expected 2, got 3",
        differences = { ".b[1]: expected 2, got 3" } },
      { name = "Beta.test_c_errors #1", case = "Beta", status = "errored", assertions = 0, duration = 0,
        message = 'hecate.core.StateError: bad "state"' },
      passed("Beta.test_d", 1) } },
    { name = "tests/unit/gamma_test.lua", tests = { passed("Gamma.test_a", 1) } },
  }
end

-- Sends `reporter` the events a runner would send for `sample()`.
local function drive(reporter)
  local suites = sample()
  local total = 0
  for _, suite in ipairs(suites) do total = total + #suite.tests end
  reporter:handle({ type = "run_started", total = total, suites = #suites })
  local summary = { total = total, passed = 0, failed = 0, errored = 0, assertions = 0, ok = true, exit_code = 0,
    results = {}, suites = {}, duration = 0 }
  for _, suite in ipairs(suites) do
    local stats = { name = suite.name, total = #suite.tests, passed = 0, failed = 0, errored = 0, assertions = 0,
      duration = 0 }
    summary.suites[#summary.suites + 1] = stats
    reporter:handle({ type = "suite_started", suite = suite.name, total = #suite.tests })
    for index, result in ipairs(suite.tests) do
      result.suite = suite.name
      reporter:handle({ type = "test_started", suite = suite.name, test = result.name, index = index })
      reporter:handle({ type = "test_finished", suite = suite.name, test = result.name, index = index, result = result })
      summary.results[#summary.results + 1] = result
      summary[result.status], stats[result.status] = summary[result.status] + 1, stats[result.status] + 1
      summary.assertions, stats.assertions = summary.assertions + result.assertions, stats.assertions + result.assertions
      if result.status ~= "passed" then summary.ok, summary.exit_code = false, 1 end
    end
    reporter:handle({ type = "suite_finished", suite = suite.name, summary = stats })
  end
  reporter:handle({ type = "run_finished", summary = summary })
end

local function capture(make, options)
  local out = {}
  options = options or {}
  options.write = function(text) out[#out + 1] = text end
  drive(make(options))
  return table.concat(out)
end

local function console(options)
  options.getenv = options.getenv or function() return nil end
  return capture(function(o) return hecate_test.ConsoleReporter(o) end, options)
end

function T:test_console_plain_output_matches_the_golden_file()
  self:assert_equal(read("console_plain.golden"), console({ color = false, live = false }))
end

function T:test_console_colored_output_matches_the_golden_file()
  self:assert_equal(read("console_color.golden"), console({ color = true, live = false }))
end

function T:test_console_live_output_matches_the_golden_file()
  self:assert_equal(read("console_live.golden"), console({ color = true, live = true }))
end

function T:test_console_output_without_colour_has_no_escape_sequences_even_when_live_is_off()
  self:assert_nil(console({ color = false, live = false }):find("\27", 1, true))
  self:assert_nil(console({ color = false, live = false }):find("\r", 1, true))
end

function T:test_the_loading_bar_is_scaled_and_a_cell_is_red_when_a_test_it_stands_for_failed()
  local out = {}
  local reporter = hecate_test.ConsoleReporter({ write = function(t) out[#out + 1] = t end, color = false, live = false,
    width = 100, getenv = function() return nil end })
  reporter:handle({ type = "run_started", total = 100, suites = 1 })
  reporter:handle({ type = "suite_started", suite = "suite", total = 100 })
  local stats = { name = "suite", total = 100, passed = 99, failed = 1, errored = 0, assertions = 100, duration = 0 }
  for index = 1, 100 do
    local status = index == 57 and "failed" or "passed"
    reporter:handle({ type = "test_finished", suite = "suite", test = "S.t" .. index, index = index,
      result = { name = "S.t" .. index, case = "S", suite = "suite", status = status, assertions = 1, duration = 0 } })
  end
  reporter:handle({ type = "suite_finished", suite = "suite", summary = stats })
  local line = out[2]
  -- 100 tests into 40 cells: test 57 stands for cell (56 * 40 // 100) + 1 = 23
  self:assert_equal("FAIL\tsuite (100 assertions, 1 failed, 0 errored) [" .. ("."):rep(22) .. "F" .. ("."):rep(17) .. "]\n", line)
  self:assert_true(#line:gsub("\n$", "") + 3 <= 100) -- the tab after a four-letter word reaches column 8
end

function T:test_a_line_never_outgrows_the_width_and_a_long_name_keeps_its_tail()
  for _, width in ipairs({ 60, 80, 120 }) do
    local out = {}
    local reporter = hecate_test.ConsoleReporter({ write = function(t) out[#out + 1] = t end, color = false, live = false,
      width = width, getenv = function() return nil end })
    local name = "packages/very/long/path/to/some/deeply/nested/directory/of/tests/unit/feature_test.lua"
    reporter:handle({ type = "suite_started", suite = name, total = 500 })
    reporter:handle({ type = "suite_finished", suite = name,
      summary = { name = name, total = 500, passed = 0, failed = 0, errored = 0, assertions = 12, duration = 0 } })
    local line = out[1]:gsub("\n$", "")
    local columns = #line + 3 -- the tab after a four-letter word reaches column 8
    self:assert_true(columns <= width, ("width %d: line has %d columns"):format(width, columns))
    self:assert_match("est%.lua ", line)
  end
end

function T:test_a_live_suite_of_thousands_of_assertions_still_fits_the_width()
  for _, width in ipairs({ 60, 80, 120 }) do
    local out = {}
    local reporter = hecate_test.ConsoleReporter({ write = function(t) out[#out + 1] = t end, color = false, live = true,
      width = width, getenv = function() return nil end })
    local name = "packages/very/long/path/to/some/deeply/nested/tests/unit/feature_test.lua"
    reporter:handle({ type = "suite_started", suite = name, total = 200 })
    for index = 1, 200 do
      reporter:handle({ type = "test_finished", index = index, result = { name = "t", case = "C", suite = name, status = "passed", assertions = 1, duration = 0 } })
    end
    reporter:handle({ type = "suite_finished", suite = name, summary = {
      name = name, total = 200, passed = 200, failed = 0, errored = 0, assertions = 1234567, duration = 0 } })
    for _, text in ipairs(out) do
      local line = text:gsub("^\r\27%[2K", ""):gsub("\n$", "")
      self:assert_true(#line + 3 <= width, ("width %d: %d columns: %s"):format(width, #line + 3, line))
    end
    self:assert_match("%(1234567 assertions", out[#out])
    self:assert_match("%[[%.F ]+%]", out[#out])
  end
end

function T:test_a_suite_of_few_tests_has_one_cell_per_test()
  local out = console({ color = false, live = false, width = 120 })
  self:assert_match("PASS\ttests/unit/alpha_test%.lua %(6 assertions, 0 failed, 0 errored%) %[%.%.%.%]\n", out)
  self:assert_match("FAIL\ttests/unit/beta_test%.lua %(4 assertions, 1 failed, 1 errored%) %[%.FF%.%]\n", out)
end

function T:test_tap_output_matches_the_golden_file()
  self:assert_equal(read("tap.golden"), capture(function(o) return hecate_test.TapReporter(o.write) end))
end

function T:test_tap_output_of_an_all_passing_run_has_no_diagnostics()
  local out = {}
  local reporter = hecate_test.TapReporter(function(text) out[#out + 1] = text end)
  reporter:handle({ type = "run_started", total = 1, suites = 1 })
  reporter:handle({ type = "suite_started", suite = "A", total = 1 })
  reporter:handle({ type = "test_started", suite = "A", test = "A.test_x", index = 1 })
  reporter:handle({ type = "test_finished", suite = "A", test = "A.test_x", index = 1,
    result = { name = "A.test_x", case = "A", suite = "A", status = "passed", assertions = 1, duration = 0 } })
  self:assert_equal("TAP version 14\n1..1\nok 1 - A.test_x\n", table.concat(out))
end

function T:test_junit_groups_tests_by_suite_and_escapes_text()
  local C = hecate_test.Case("Xml")
  function C:test_ok() self:assert_true(true) end
  function C:test_bad() self:assert_equal("<a&b>", "c\1") end
  function C:test_err() error("boom \"x\"", 0) end
  local out = {}
  local summary = hecate_test.Runner({ reporter = hecate_test.JUnitReporter(function(t) out[#out + 1] = t end) }):run({ C })
  local text = table.concat(out)
  self:assert_match('^<%?xml version="1%.0" encoding="UTF%-8"%?>\n<testsuites tests="3" failures="1" errors="1" time="', text)
  self:assert_match('<testsuite name="Xml" tests="3" failures="1" errors="1" skipped="0"', text)
  self:assert_match('<testcase classname="Xml" name="test_ok" time="[%d%.]+"/>', text)
  self:assert_match('<failure message="[^"]*" type="AssertionFailure">', text)
  self:assert_match('<error message="boom &quot;x&quot;" type="Error">', text)
  self:assert_nil(text:find("<a&b>", 1, true))
  self:assert_nil(text:find("\1", 1, true))
  self:assert_equal(2, summary.failed + summary.errored)
end

function T:test_json_lines_output_matches_the_golden_file()
  self:assert_equal(read("events.jsonl.golden"), capture(function(o) return hecate_test.JsonLinesReporter(o.write) end))
end

function T:test_json_lines_writes_one_decodable_object_per_line_without_escape_sequences()
  local json = require("hecate.json")
  local text = capture(function(o) return hecate_test.JsonLinesReporter(o.write) end)
  self:assert_nil(text:find("\27", 1, true))
  local kinds = {}
  for line in text:gmatch("[^\n]+") do kinds[#kinds + 1] = json.decode(line).type end
  self:assert_equal(#text:gsub("[^\n]", ""), #kinds)
  self:assert_equal("run_started", kinds[1])
  self:assert_equal("run_finished", kinds[#kinds])
end

function T:test_a_real_run_keeps_the_tap_plan_exact_and_the_event_stream_complete()
  local C = hecate_test.Case("Real")
  function C:tear_down_case() error("late", 0) end
  function C:test_a() self:assert_true(true) end
  function C:test_b() self:assert_equal(1, 2) end
  function C:test_c() self:assert_true(true) end
  local tap, lines = {}, {}
  local json = require("hecate.json")
  local summary = hecate_test.Runner({ reporter = hecate_test.TapReporter(function(t) tap[#tap + 1] = t end) }):run({ C })
  hecate_test.Runner({ reporter = hecate_test.JsonLinesReporter(function(t) lines[#lines + 1] = t end) }):run({ C })
  local text = table.concat(tap)
  self:assert_match("^TAP version 14\n1%.%.3\n", text)
  local points = 0
  for _ in text:gmatch("\n[^\n ]*%s?ok %d+ %- ") do points = points + 1 end
  self:assert_equal(3, points)
  self:assert_match("not ok 3 %- Real%.test_c", text) -- tear_down_case failed: reported on the last test
  self:assert_equal(1, summary.exit_code)
  local finished = {}
  for _, line in ipairs(lines) do
    self:assert_equal("\n", line:sub(-1))
    local event = json.decode(line)
    if event.type == "test_finished" then finished[#finished + 1] = event.test .. ":" .. event.status .. ":" .. event.assertions end
  end
  self:assert_equal({ "Real.test_a:passed:1", "Real.test_b:failed:1", "Real.test_c:errored:1" }, finished)
end

return require("hecate.core").finalise(T)
