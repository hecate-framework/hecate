-- Line coverage: the lines of the sources that ran, in the main thread and in coroutines, as an LCOV report.
global <const> require, debug, coroutine, dofile, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local hecate_test = require("hecate.test")

local T = hecate_test.Case("LineCoverageTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local fixtures = here .. "/../fixtures/coverage"
local INCLUDE = "fixtures/coverage/"

local function normal(path) return (path:gsub("\\", "/")) end

local function hit_lines(coverage, name)
  for path, lines in pairs(coverage:hits()) do
    if path:find(name, 1, true) then return lines end
  end
  return {}
end

function T:test_the_lines_that_ran_are_recorded_and_the_others_reported_as_missed()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  coverage:start()
  local sample = dofile(fixtures .. "/sample.lua")
  self:assert_equal("positive", sample.pick(1))
  coverage:stop()
  local lines = hit_lines(coverage, "sample.lua")
  self:assert_true(lines[3] ~= nil and lines[4] ~= nil, "the taken branch")
  self:assert_nil(lines[6])
  local report = coverage:report()
  self:assert_equal(1, #report.files)
  self:assert_true(report.files[1].covered < report.files[1].total)
  self:assert_true(report.percent > 0 and report.percent < 100)
  local text = coverage:lcov()
  self:assert_match("SF:[^\n]*sample%.lua\n", text)
  self:assert_match("DA:4,[1-9]", text)
  self:assert_match("DA:6,0\n", text)
  self:assert_match("LF:%d+\nLH:%d+\nend_of_record", text)
end

function T:test_lines_run_in_coroutines_are_recorded()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  coverage:start()
  local sample = dofile(fixtures .. "/sample.lua")
  local co = coroutine.create(function() return sample.pick(-1) end)
  local ok, value = coroutine.resume(co)
  local wrapped = coroutine.wrap(function() return sample.pick(5) end)()
  coverage:stop()
  self:assert_true(ok)
  self:assert_equal("other", value)
  self:assert_equal("positive", wrapped)
  local lines = hit_lines(coverage, "sample.lua")
  self:assert_true(lines[4] ~= nil and lines[6] ~= nil)
end

function T:test_stopping_restores_the_hook_and_the_coroutine_functions()
  local create, wrap, hook = coroutine.create, coroutine.wrap, debug.gethook()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  coverage:start()
  self:assert_error(function() coverage:start() end, { class = core.StateError })
  coverage:stop()
  self:assert_equal(create, coroutine.create)
  self:assert_equal(wrap, coroutine.wrap)
  self:assert_equal(hook, debug.gethook())
  self:assert_error(function() coverage:stop() end, { class = core.StateError })
end

function T:test_a_region_marked_off_is_not_counted()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  coverage:start()
  dofile(fixtures .. "/regions.lua").run()
  coverage:stop()
  local text = coverage:lcov()
  self:assert_nil(text:find("DA:7,", 1, true))
  self:assert_equal(100, coverage:report().percent)
end

function T:test_include_exclude_and_merge()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE, exclude = "regions" })
  coverage:start()
  dofile(fixtures .. "/sample.lua").pick(1)
  dofile(fixtures .. "/regions.lua").run()
  coverage:stop()
  self:assert_equal(1, #coverage:report().files)
  local other = hecate_test.LineCoverage({ include = INCLUDE })
  other:merge(coverage:hits())
  other:merge(coverage:hits())
  local path = coverage:report().files[1].path
  self:assert_equal(2 * coverage:hits()[path][3], other:hits()[path][3])
  self:assert_true(other:percent("sample") > 0)
  self:assert_nil(other:percent("nothing-matches"))
end

function T:test_the_runner_records_while_it_runs_and_stops_afterwards()
  local C = hecate_test.Case("Covered")
  function C:test_x() self:assert_equal("positive", dofile(fixtures .. "/sample.lua").pick(1)) end
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  local before = debug.gethook()
  local summary = hecate_test.Runner({ coverage = coverage }):run({ C })
  self:assert_true(summary.ok)
  self:assert_equal(before, debug.gethook())
  self:assert_true(hit_lines(coverage, "sample.lua")[4] ~= nil)
end

function T:test_workers_report_their_lines_to_the_coordinator()
  local coverage = hecate_test.LineCoverage({ include = INCLUDE })
  local summary = reactor.run(hecate_test.run_parallel, { normal(here .. "/../fixtures/parallel/d_case.lua") },
    { coverage = coverage })
  self:assert_true(summary.ok)
  self:assert_true(hit_lines(coverage, "sample.lua")[4] ~= nil)
end

function T:test_bad_options_raise_argument_error()
  ---@type any
  local number, unknown = 1, { nope = true }
  self:assert_error(function() hecate_test.LineCoverage(number) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.LineCoverage(unknown) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.Runner({ coverage = number }) end, { class = core.ArgumentError })
  self:assert_error(function()
    reactor.run(hecate_test.run_parallel, {}, { coverage = number })
  end, { class = core.ArgumentError })
end

return core.finalise(T)
