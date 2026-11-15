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

-- A summary built by hand: deterministic, no locations that depend on this file's lines.
local function sample_results()
  return {
    { name = "Sample.test_a_passes", case = "Sample", status = "passed", duration = 0 },
    { name = "Sample.test_b_fails", case = "Sample", status = "failed", duration = 0, location = "tests/sample_test.lua:12",
      message = "tables differ:\n  .b[1]: expected 2, got 3", differences = { ".b[1]: expected 2, got 3" } },
    { name = "Sample.test_c_errors #1", case = "Sample", status = "errored", duration = 0,
      message = 'hecate.core.StateError: bad "state"' },
  }
end

local function drive(reporter)
  local results = sample_results()
  reporter:start({ total = #results })
  local summary = { total = 3, passed = 1, failed = 1, errored = 1, ok = false, results = results, duration = 0 }
  for _, r in ipairs(results) do reporter:report(r) end
  reporter:finish(summary)
end

function T:test_console_output_matches_the_golden_file()
  local out = {}
  drive(hecate_test.ConsoleReporter(function(text) out[#out + 1] = text end))
  self:assert_equal(read("console.golden"), table.concat(out))
end

function T:test_tap_output_matches_the_golden_file()
  local out = {}
  drive(hecate_test.TapReporter(function(text) out[#out + 1] = text end))
  self:assert_equal(read("tap.golden"), table.concat(out))
end

function T:test_tap_output_of_an_all_passing_run_has_no_diagnostics()
  local out = {}
  local reporter = hecate_test.TapReporter(function(text) out[#out + 1] = text end)
  reporter:start({ total = 1 })
  reporter:report({ name = "A.test_x", case = "A", status = "passed", duration = 0 })
  self:assert_equal("TAP version 14\n1..1\nok 1 - A.test_x\n", table.concat(out))
end

return require("hecate.core").finalise(T)
