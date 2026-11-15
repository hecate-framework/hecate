local core = require("hecate.core")
local reactor = require("hecate.reactor")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("ParallelTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local fixtures = here .. "/../fixtures/parallel"

local function run(paths, options)
  local events = {}
  options = options or {}
  options.reporter = { handle = function(_, event) events[#events + 1] = event end }
  local summary = reactor.run(hecate_test.run_parallel, paths, options)
  return summary, events
end

function T:test_files_run_in_workers_and_replay_in_path_order()
  local summary, events = run({ fixtures .. "/b_case.lua", fixtures .. "/a_case.lua" }, { jobs = 2 })
  self:assert_equal(3, summary.total)
  self:assert_equal(2, summary.passed)
  self:assert_equal(1, summary.failed)
  self:assert_false(summary.ok)
  self:assert_equal(1, summary.exit_code)
  self:assert_equal("run_started", events[1].type)
  self:assert_equal(3, events[1].total)
  self:assert_equal(2, events[1].suites)
  self:assert_equal("run_finished", events[#events].type)
  self:assert_equal({ "ParallelB.test_fails", "ParallelA.test_one", "ParallelA.test_two" },
    { summary.results[1].name, summary.results[2].name, summary.results[3].name })
end

function T:test_runner_options_reach_the_workers()
  local summary = run({ fixtures .. "/a_case.lua" }, { runner = { filter = "test_two" } })
  self:assert_equal(1, summary.total)
  self:assert_true(summary.ok)
end

function T:test_a_file_that_does_not_load_is_an_errored_suite()
  local summary = run({ fixtures .. "/c_case.lua" })
  self:assert_equal(1, summary.errored)
  self:assert_true(summary.results[1].message:find("does not load", 1, true) ~= nil)
end

function T:test_one_job_gives_the_same_result()
  local summary = run({ fixtures .. "/a_case.lua", fixtures .. "/b_case.lua" }, { jobs = 1 })
  self:assert_equal(3, summary.total)
end

function T:test_jobs_must_be_a_positive_integer()
  self:assert_error(function() run({}, { jobs = 0 }) end, { class = core.ArgumentError })
end

return core.finalise(T)
