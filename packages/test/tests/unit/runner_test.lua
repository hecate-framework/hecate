local core = require("hecate.core")
local reactor = require("hecate.reactor")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("RunnerTest")

local function run(cases, options)
  return hecate_test.Runner(options):run(cases)
end

local function statuses(summary)
  local out = {}
  for _, r in ipairs(summary.results) do out[r.name] = r.status end
  return out
end

function T:test_passing_tests_are_reported_in_name_order()
  local C = hecate_test.Case("C")
  function C:test_b() end
  function C:test_a() end
  local summary = run({ C })
  self:assert_true(summary.ok)
  self:assert_equal(2, summary.passed)
  self:assert_equal("C.test_a", summary.results[1].name)
  self:assert_equal("C.test_b", summary.results[2].name)
end

function T:test_a_failed_assertion_is_a_failure_with_its_location()
  local C = hecate_test.Case("C")
  function C:test_x() self:assert_equal(1, 2) end
  local summary = run({ C })
  self:assert_false(summary.ok)
  local r = summary.results[1]
  self:assert_equal("failed", r.status)
  self:assert_equal("expected 1, got 2", r.message)
  self:assert_match("runner_test%.lua:%d+$", r.location)
end

function T:test_any_other_raise_is_an_error_with_a_traceback()
  local C = hecate_test.Case("C")
  function C:test_x() error("kaput", 0) end
  function C:test_y() error(core.StateError("bad state")) end
  local summary = run({ C })
  self:assert_equal(2, summary.errored)
  self:assert_equal("kaput", summary.results[1].message)
  self:assert_match("stack traceback", summary.results[1].traceback)
  self:assert_equal("hecate.core.StateError: bad state", summary.results[2].message)
end

function T:test_a_failing_test_never_affects_another()
  local C = hecate_test.Case("C")
  function C:test_a_fails() self:fail("no") end
  function C:test_b_errors() error("no", 0) end
  function C:test_c_passes() end
  local summary = run({ C })
  self:assert_equal({ ["C.test_a_fails"] = "failed", ["C.test_b_errors"] = "errored", ["C.test_c_passes"] = "passed" },
    statuses(summary))
end

function T:test_each_test_has_a_fresh_instance()
  local C = hecate_test.Case("C")
  function C:test_a() self:assert_nil(self.counter); self.counter = 1 end
  function C:test_b() self:assert_nil(self.counter); self.counter = 1 end
  self:assert_true(run({ C }).ok)
end

function T:test_lifecycle_runs_in_order_and_tear_down_runs_after_a_failure()
  local log = {}
  local C = hecate_test.Case("C")
  function C:set_up_case() log[#log + 1] = "set_up_case"; self.shared = "s" end
  function C:tear_down_case() log[#log + 1] = "tear_down_case" end
  function C:set_up() log[#log + 1] = "set_up" end
  function C:tear_down() log[#log + 1] = "tear_down" end
  function C:test_a() log[#log + 1] = "test_a:" .. self.shared end
  function C:test_b() log[#log + 1] = "test_b"; self:fail() end
  run({ C })
  self:assert_equal({ "set_up_case", "set_up", "test_a:s", "tear_down", "set_up", "test_b", "tear_down", "tear_down_case" }, log)
end

function T:test_a_failing_set_up_skips_the_test_and_its_tear_down()
  local log = {}
  local C = hecate_test.Case("C")
  function C:set_up() error("setup broke", 0) end
  function C:tear_down() log[#log + 1] = "tear_down" end
  function C:test_a() log[#log + 1] = "test_a" end
  local summary = run({ C })
  self:assert_equal("errored", summary.results[1].status)
  self:assert_equal("set_up: setup broke", summary.results[1].message)
  self:assert_equal(0, #log)
end

function T:test_a_failing_tear_down_fails_a_passing_test_but_keeps_an_earlier_failure()
  local C = hecate_test.Case("C")
  function C:tear_down() error("td", 0) end
  function C:test_a() end
  function C:test_b() self:fail("first") end
  local summary = run({ C })
  self:assert_equal("tear_down: td", summary.results[1].message)
  self:assert_equal("first", summary.results[2].message)
end

function T:test_a_failing_set_up_case_errors_every_test_of_the_case_only()
  local C = hecate_test.Case("C")
  function C:set_up_case() error("no db", 0) end
  function C:test_a() end
  function C:test_b() end
  local D = hecate_test.Case("D")
  function D:test_a() end
  local summary = run({ C, D })
  self:assert_equal(2, summary.errored)
  self:assert_equal("set_up_case: no db", summary.results[1].message)
  self:assert_equal("passed", summary.results[3].status)
end

function T:test_a_failing_tear_down_case_is_reported_on_the_last_test()
  local C = hecate_test.Case("C")
  function C:tear_down_case() error("late", 0) end
  function C:test_a() end
  function C:test_b() end
  local summary = run({ C })
  self:assert_equal("passed", summary.results[1].status)
  self:assert_equal("tear_down_case: late", summary.results[2].message)
end

function T:test_tests_run_inside_a_reactor_and_may_suspend()
  local C = hecate_test.Case("C")
  function C:test_sleeps() reactor.sleep(0.001); self:assert_true(reactor.now() > 0) end
  function C:test_joins_a_fork() self:assert_equal(3, reactor.join(reactor.fork(function() reactor.sleep(0.001); return 3 end))) end
  self:assert_true(run({ C }).ok)
end

function T:test_an_assertion_failing_in_a_forked_coroutine_fails_the_test()
  local C = hecate_test.Case("C")
  function C:test_x()
    reactor.fork(function() self:assert_equal(1, 2) end)
    reactor.sleep(0.01)
  end
  local r = run({ C }).results[1]
  self:assert_equal("failed", r.status)
  self:assert_equal("expected 1, got 2", r.message)
end

function T:test_a_test_that_leaks_a_coroutine_fails_and_the_leak_is_cancelled()
  local C = hecate_test.Case("C")
  local finished = false
  function C:test_a_leaks() reactor.fork(function() reactor.sleep(30); finished = true end) end
  function C:test_b_clean() end
  local summary = run({ C })
  self:assert_equal("failed", summary.results[1].status)
  self:assert_equal("leaked 1 coroutine(s): the test left them running", summary.results[1].message)
  self:assert_equal("passed", summary.results[2].status)
  self:assert_false(finished)
end

function T:test_a_detached_leak_fails_the_test_without_hanging()
  local C = hecate_test.Case("C")
  function C:test_a_leaks() reactor.detach(function() reactor.sleep(30) end) end
  function C:test_b_after() end
  local summary = run({ C })
  self:assert_equal("failed", summary.results[1].status)
  self:assert_match("^leaked 1 coroutine", summary.results[1].message)
  self:assert_equal("passed", summary.results[2].status)
end

function T:test_a_test_that_joins_what_it_forks_does_not_leak()
  local C = hecate_test.Case("C")
  function C:test_x() reactor.join(reactor.fork(function() reactor.sleep(0.001) end)) end
  self:assert_true(run({ C }).ok)
end

function T:test_a_deadlocked_test_errors_instead_of_hanging()
  local C = hecate_test.Case("C")
  function C:test_x() reactor.Channel():receive() end
  local r = run({ C }).results[1]
  self:assert_equal("errored", r.status)
  self:assert_match("deadlock", r.message)
end

function T:test_the_filter_selects_tests_by_full_name()
  local C = hecate_test.Case("C")
  function C:test_alpha() end
  function C:test_beta() end
  local summary = run({ C }, { filter = "alpha$" })
  self:assert_equal(1, summary.total)
  self:assert_equal("C.test_alpha", summary.results[1].name)
end

function T:test_the_reporter_receives_plan_results_and_summary()
  local events = {}
  local reporter = {
    start = function(_, plan) events[#events + 1] = "start:" .. plan.total end,
    report = function(_, r) events[#events + 1] = r.name .. ":" .. r.status end,
    finish = function(_, s) events[#events + 1] = "finish:" .. s.passed end,
  }
  local C = hecate_test.Case("C")
  function C:test_a() end
  run({ C }, { reporter = reporter })
  self:assert_equal({ "start:1", "C.test_a:passed", "finish:1" }, events)
end

function T:test_running_something_that_is_not_a_case_raises()
  self:assert_error(function() run({ {} }) end, { class = core.ArgumentError })
  ---@diagnostic disable-next-line: assign-type-mismatch  -- the argument error is the point
  self:assert_error(function() hecate_test.Runner({ filter = 1 }) end, { class = core.ArgumentError })
end

return require("hecate.core").finalise(T)
