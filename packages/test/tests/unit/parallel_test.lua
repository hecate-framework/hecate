global <const> require, ipairs, debug
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
  local summary = run({ fixtures .. "/a_case.lua" }, { filter = "test_two" })
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

function T:test_a_corrupt_result_is_an_errored_suite_and_the_run_goes_on()
  local summary = run({ fixtures .. "/e_case.lua", fixtures .. "/a_case.lua" }, { jobs = 1 })
  self:assert_equal(1, summary.errored)
  self:assert_equal(2, summary.passed)
  self:assert_match("unreadable", summary.results[1].message)
end

function T:test_a_worker_that_exits_without_a_result_is_an_errored_suite()
  local summary = run({ fixtures .. "/f_case.lua" })
  self:assert_equal(1, summary.errored)
  self:assert_match("code 3", summary.results[1].message)
end

function T:test_what_a_test_prints_to_standard_output_is_dropped()
  local summary = run({ fixtures .. "/g_case.lua" })
  self:assert_true(summary.ok)
  self:assert_equal(1, summary.passed)
end

function T:test_failing_workers_never_hold_the_other_files_back()
  local paths = {}
  for _, name in ipairs({ "a_case", "e_case", "f_case", "b_case", "e_case", "g_case" }) do
    paths[#paths + 1] = fixtures .. "/" .. name .. ".lua"
  end
  local summary = run(paths, { jobs = 2 })
  -- a_case (2 tests) and b_case (1 failing) and g_case (1) run; e_case (twice) and f_case are errored suites
  self:assert_equal(3, summary.errored)
  self:assert_equal(3, summary.passed)
  self:assert_equal(1, summary.failed)
end

function T:test_events_reach_the_reporter_while_the_files_still_run()
  local times = {}
  local reporter = { handle = function(_, event)
    times[#times + 1] = { type = event.type, name = event.test, at = reactor.now() }
  end }
  local summary = reactor.run(hecate_test.run_parallel, { fixtures .. "/slow_case.lua" }, { reporter = reporter })
  self:assert_true(summary.ok)
  local fast, finished
  for _, entry in ipairs(times) do
    if entry.type == "test_finished" and entry.name == "ParallelSlow.test_a_fast" then fast = entry.at end
    if entry.type == "run_finished" then finished = entry.at end
  end
  self:assert_true(fast ~= nil and finished ~= nil)
  self:assert_true(finished - fast >= 0.3, ("the first result came %.2f s before the end"):format(finished - fast))
end

function T:test_the_plan_is_known_before_the_first_event()
  local _, events = run({ fixtures .. "/a_case.lua", fixtures .. "/b_case.lua" })
  self:assert_equal("run_started", events[1].type)
  self:assert_equal(3, events[1].total)
  self:assert_equal(2, events[1].suites)
  self:assert_equal("suite_started", events[2].type)
end

function T:test_an_empty_list_is_an_empty_successful_run()
  local summary = run({})
  self:assert_equal(0, summary.total)
  self:assert_true(summary.ok)
  self:assert_true(summary.empty)
end

function T:test_a_missing_interpreter_is_an_errored_suite_not_an_error()
  local summary = run({ fixtures .. "/a_case.lua" }, { lua = fixtures .. "/no-such-interpreter" })
  self:assert_equal(1, summary.errored)
  self:assert_match("cannot start a worker", summary.results[1].message)
end

function T:test_the_interpreter_is_the_smallest_index_of_arg()
  local parallel = require("hecate.test.parallel")
  self:assert_equal("lua55", parallel.interpreter({ [0] = "s.lua", [-1] = "-W", [-2] = "lua55" }))
  self:assert_equal("lua", parallel.interpreter({ [0] = "s.lua", [-1] = "lua" }))
  self:assert_equal("lua", parallel.interpreter({ [0] = "s.lua", [-1] = "-e", [-2] = "x=1", [-3] = "lua" }))
  self:assert_nil(parallel.interpreter(nil))
  self:assert_nil(parallel.interpreter({ [0] = "s.lua" }))
end

function T:test_a_recorder_with_a_predicate_cannot_be_used_by_workers()
  local coverage = hecate_test.LineCoverage({ include = function() return true end })
  self:assert_error(function() run({ fixtures .. "/a_case.lua" }, { coverage = coverage }) end,
    { class = core.ArgumentError })
end

function T:test_options_are_flat_and_unknown_ones_are_refused()
  local summary = run({ fixtures .. "/a_case.lua" }, { cases = { "ParallelA" }, tags = nil, exclude_tags = { "none" } })
  self:assert_equal(2, summary.total)
  ---@type any
  local nested, typo = { runner = { filter = "x" } }, { job = 2 }
  self:assert_error(function() run({}, nested) end, { class = core.ArgumentError })
  self:assert_error(function() run({}, typo) end, { class = core.ArgumentError })
end

return core.finalise(T)
