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
  C.clock = "virtual" -- the sleep of the leak costs no time
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
  C.clock = "virtual"
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

function T:test_tags_select_and_exclude_tests_of_a_case_or_of_a_single_test()
  local C = hecate_test.Case("Tagged")
  C.tags = { "unit" }
  C.test_tags = { test_b = { "slow" }, test_c = { "slow", "net" } }
  function C:test_a() end
  function C:test_b() end
  function C:test_c() end
  local function names(options)
    local list = {}
    for _, t in ipairs(hecate_test.Runner(options):plan({ C })) do list[#list + 1] = t.name end
    return table.concat(list, ",")
  end
  self:assert_equal("test_a,test_b,test_c", names({ tags = { "unit" } }))
  self:assert_equal("test_b,test_c", names({ tags = { "slow" } }))
  self:assert_equal("test_c", names({ tags = { "net", "nothing" } }))
  self:assert_equal("test_a", names({ exclude_tags = { "slow" } }))
  self:assert_equal("test_b", names({ tags = { "slow" }, exclude_tags = { "net" } }))
  self:assert_equal("test_a,test_b,test_c", names({}))
  ---@type any
  local text = "slow"
  ---@type any
  local numbers = { 1 }
  self:assert_error(function() hecate_test.Runner({ tags = text }) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.Runner({ exclude_tags = numbers }) end, { class = core.ArgumentError })
end

function T:test_a_parametrised_test_runs_once_per_entry_with_its_own_name_and_result()
  local C = hecate_test.Case("Param")
  C.test_parameters = { test_add = { { label = "small", 1, 2, 3 }, { 2, 2, 5 }, { label = "big", 10, 20, 30 } } }
  local seen = {}
  function C:test_add(entry)
    seen[#seen + 1] = entry[1] .. "+" .. entry[2]
    self:assert_equal(entry[3], entry[1] + entry[2])
  end
  function C:test_plain() end
  local summary = run({ C })
  self:assert_equal("1+2,2+2,10+20", table.concat(seen, ","))
  self:assert_equal(4, summary.total)
  self:assert_equal(1, summary.failed)
  local names = {}
  for _, r in ipairs(summary.results) do names[#names + 1] = r.name .. ":" .. r.status end
  self:assert_equal("Param.test_add[small]:passed,Param.test_add[2]:failed,Param.test_add[big]:passed,Param.test_plain:passed",
    table.concat(names, ","))
end

function T:test_parameter_entries_are_selectable_by_filter_and_bad_declarations_raise()
  local C = hecate_test.Case("Sel")
  C.test_parameters = { test_x = { { label = "a" }, { label = "b" } } }
  function C:test_x() end
  self:assert_equal(1, #hecate_test.Runner({ filter = "%[b%]$" }):plan({ C }))
  C.test_parameters = { test_x = {} }
  self:assert_error(function() hecate_test.Runner():plan({ C }) end, { class = core.ArgumentError })
  C.test_parameters = { test_x = { { label = "a" }, { label = "a" } } }
  self:assert_error(function() hecate_test.Runner():plan({ C }) end, { class = core.ArgumentError })
end

function T:test_a_virtual_clock_makes_sleeps_instant_and_a_case_can_choose_it()
  local reactor = require("hecate.reactor")
  local C = hecate_test.Case("Virtual")
  C.clock = "virtual"
  function C:test_sleep()
    local before = reactor.now()
    reactor.sleep(3600)
    self:assert_equal(3600, reactor.now() - before)
  end
  local R = hecate_test.Case("Real")
  function R:test_is_real() self:assert_true(reactor.now() >= 0) end
  local started = os.clock()
  local summary = run({ C, R })
  self:assert_true(summary.ok)
  self:assert_true(os.clock() - started < 5)
  local all = run({ (function()
    local D = hecate_test.Case("Opt")
    function D:test_sleep() reactor.sleep(1000) end
    return D
  end)() }, { clock = "virtual" })
  self:assert_true(all.ok)
  ---@type any
  local fast = "fast"
  self:assert_error(function() hecate_test.Runner({ clock = fast }) end, { class = core.ArgumentError })
end

function T:test_the_filter_selects_tests_by_full_name()
  local C = hecate_test.Case("C")
  function C:test_alpha() end
  function C:test_beta() end
  local summary = run({ C }, { filter = "alpha$" })
  self:assert_equal(1, summary.total)
  self:assert_equal("C.test_alpha", summary.results[1].name)
end

local function recorder()
  local events = {}
  return events, { handle = function(_, event) events[#events + 1] = event end }
end

local function describe(events)
  local out = {}
  for i, e in ipairs(events) do
    local detail = e.test or e.suite or ""
    if e.type == "test_finished" then detail = e.test .. ":" .. e.result.status end
    out[i] = e.type .. (detail ~= "" and (" " .. detail) or "")
  end
  return out
end

function T:test_the_reporter_receives_the_events_of_the_run_as_they_happen()
  local events, reporter = recorder()
  local C = hecate_test.Case("C")
  function C:test_a() end
  function C:test_b() self:fail("no") end
  run({ C }, { reporter = reporter })
  self:assert_equal({
    "run_started", "suite_started C", "test_started C.test_a", "test_finished C.test_a:passed",
    "test_started C.test_b", "test_finished C.test_b:failed", "suite_finished C", "run_finished",
  }, describe(events))
  self:assert_equal({ total = 2, suites = 1 }, { total = events[1].total, suites = events[1].suites })
  self:assert_equal(2, events[2].total)
  self:assert_equal(2, events[#events - 1].summary.total)
  self:assert_equal(1, events[#events].summary.failed)
end

function T:test_a_test_is_announced_before_it_runs_and_reported_after()
  local log = {}
  local reporter = { handle = function(_, e) if e.type:find("^test_") then log[#log + 1] = e.type end end }
  local C = hecate_test.Case("C")
  function C:test_a() log[#log + 1] = "body" end
  run({ C }, { reporter = reporter })
  self:assert_equal({ "test_started", "body", "test_finished" }, log)
end

function T:test_a_test_finishes_as_soon_as_it_has_run_except_the_last_of_a_case_that_waits_for_tear_down_case()
  local log = {}
  local reporter = { handle = function(_, e) if e.type == "test_finished" then log[#log + 1] = e.test end end }
  local C = hecate_test.Case("C")
  function C:tear_down_case() log[#log + 1] = "tear_down_case" end
  function C:test_a() log[#log + 1] = "a" end
  function C:test_b() log[#log + 1] = "b" end
  run({ C }, { reporter = reporter })
  self:assert_equal({ "a", "C.test_a", "b", "tear_down_case", "C.test_b" }, log)
end

function T:test_the_suite_is_the_case_by_default_and_groups_the_events_of_its_tests()
  local events, reporter = recorder()
  local A, B = hecate_test.Case("A"), hecate_test.Case("B")
  function A:test_1() end
  function A:test_2() end
  function B:test_1() self:fail("no") end
  local summary = run({ A, B }, { reporter = reporter })
  self:assert_equal({ "A", "B" }, { summary.suites[1].name, summary.suites[2].name })
  self:assert_equal({ 2, 0, 1 }, { summary.suites[1].total, summary.suites[1].failed, summary.suites[2].failed })
  self:assert_equal("B", summary.results[3].suite)
  self:assert_equal(2, events[1].suites)
end

function T:test_a_loaded_case_is_a_suite_named_after_its_file()
  local fixtures = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or ".") .. "/../fixtures/discovery"
  local case = hecate_test.load(fixtures .. "/a_test.lua")
  local summary = run({ case })
  self:assert_equal(fixtures .. "/a_test.lua", summary.suites[1].name)
end

function T:test_assertions_are_counted_per_test_whether_they_pass_or_fail()
  local C = hecate_test.Case("C")
  function C:test_a_three() self:assert_true(true); self:assert_equal(1, 1); self:assert_nil(nil) end
  function C:test_b_fails_on_the_second() self:assert_true(true); self:assert_equal(1, 2); self:assert_true(true) end
  function C:test_c_none() end
  function C:test_d_nested() self:assert_error(function() error("x") end) end
  local summary = run({ C })
  self:assert_equal({ 3, 2, 0, 1 }, {
    summary.results[1].assertions, summary.results[2].assertions, summary.results[3].assertions,
    summary.results[4].assertions })
  self:assert_equal(6, summary.assertions)
  self:assert_equal(6, summary.suites[1].assertions)
end

function T:test_assertions_of_set_up_and_tear_down_count_for_the_test_but_those_of_the_case_hooks_do_not()
  local C = hecate_test.Case("C")
  function C:set_up_case() self:assert_true(true) end
  function C:set_up() self:assert_true(true) end
  function C:tear_down() self:assert_true(true) end
  function C:tear_down_case() self:assert_true(true) end
  function C:test_a() self:assert_true(true) end
  self:assert_equal(3, run({ C }).results[1].assertions)
end

function T:test_assertions_made_outside_a_run_are_not_counted_into_the_next_test()
  local C = hecate_test.Case("C")
  function C:test_a() end
  require("hecate.test.case").Base.assert_true({}, true) -- a call outside any run
  self:assert_equal(0, run({ C }).results[1].assertions)
end

function T:test_the_exit_code_is_zero_when_every_test_passed_and_one_otherwise()
  local C = hecate_test.Case("C")
  function C:test_a() end
  self:assert_equal(0, run({ C }).exit_code)
  local D = hecate_test.Case("D")
  function D:test_a() error("x", 0) end
  local summary = run({ D })
  self:assert_equal(1, summary.exit_code)
  self:assert_false(summary.ok)
end

function T:test_a_run_without_tests_emits_only_the_run_events()
  local events, reporter = recorder()
  local C = hecate_test.Case("C")
  function C:test_a() end
  run({ C }, { reporter = reporter, filter = "nothing" })
  self:assert_equal({ "run_started", "run_finished" }, describe(events))
end

function T:test_running_something_that_is_not_a_case_raises()
  self:assert_error(function() run({ {} }) end, { class = core.ArgumentError })
  ---@diagnostic disable-next-line: assign-type-mismatch  -- the argument error is the point
  self:assert_error(function() hecate_test.Runner({ filter = 1 }) end, { class = core.ArgumentError })
end

-- A test runs inside a reactor, and a reactor cannot start inside another: the inner run reports its tests as errored.
-- What must hold is that the outer test keeps its assertion counter and its clock.
function T:test_a_runner_inside_a_test_leaves_the_outer_counter_and_clock_alone()
  local Outer = hecate_test.Case("Outer")
  Outer.clock = "virtual"
  function Outer:test_a_nested()
    self:assert_true(true)
    local Inner = hecate_test.Case("Inner")
    function Inner:test_y() self:assert_true(true) end
    local inner = hecate_test.Runner():run({ Inner })
    self:assert_equal("errored", inner.results[1].status)
    self:assert_match("already running", inner.results[1].message)
    self:assert_true(true)
  end
  function Outer:test_b_virtual_clock_still_applies()
    local started = os.time()
    reactor.sleep(2)
    self:assert_true(os.time() - started < 2, "the clock of the case was lost")
  end
  local summary = run({ Outer })
  self:assert_true(summary.ok)
  self:assert_equal(4, summary.results[1].assertions)
  self:assert_equal(1, summary.results[2].assertions)
end

function T:test_a_run_without_tests_is_marked_empty()
  self:assert_true(run({}).empty)
  local C = hecate_test.Case("C")
  function C:test_x() end
  self:assert_false(run({ C }).empty)
  self:assert_true(run({ C }, { filter = "nothing" }).empty)
end

function T:test_unknown_runner_options_are_refused()
  ---@type any
  local typo = { exclude_tag = { "slow" } }
  self:assert_error(function() hecate_test.Runner(typo) end, { class = core.ArgumentError })
  ---@type any
  local not_a_table = "filter"
  self:assert_error(function() hecate_test.Runner(not_a_table) end, { class = core.ArgumentError })
end

function T:test_a_tear_down_case_failure_is_kept_when_the_last_test_failed()
  local C = hecate_test.Case("C")
  function C:test_a() self:assert_equal(1, 2) end
  function C:tear_down_case() error("cleanup went wrong", 0) end
  local summary = run({ C })
  self:assert_equal(1, summary.failed)
  self:assert_equal("failed", summary.results[1].status)
  self:assert_match("expected 1, got 2", summary.results[1].message)
  self:assert_match("cleanup went wrong", summary.results[1].message)
end

function T:test_tear_down_does_not_run_after_a_set_up_that_failed()
  local order = {}
  local C = hecate_test.Case("C")
  function C:set_up() order[#order + 1] = "set_up" if #order > 2 then error("set_up failed", 0) end end
  function C:tear_down() order[#order + 1] = "tear_down" end
  function C:test_a() end
  function C:test_b() end
  local summary = run({ C })
  self:assert_equal("passed", summary.results[1].status)
  self:assert_equal("errored", summary.results[2].status)
  self:assert_equal({ "set_up", "tear_down", "set_up" }, order)
end

function T:test_tear_down_case_does_not_run_when_set_up_case_failed()
  local calls = {}
  local C = hecate_test.Case("C")
  function C:set_up_case() calls[#calls + 1] = "set_up_case"; error("no fixture", 0) end
  function C:tear_down_case() calls[#calls + 1] = "tear_down_case" end
  function C:test_a() end
  local summary = run({ C })
  self:assert_equal("errored", summary.results[1].status)
  self:assert_equal({ "set_up_case" }, calls)
end

function T:test_virtual_timers_fire_in_order_and_cancellation_works()
  local C = hecate_test.Case("C")
  C.clock = "virtual"
  function C:test_order()
    local order = {}
    local late = reactor.fork(function() reactor.sleep(5); order[#order + 1] = "late" end)
    local early = reactor.fork(function() reactor.sleep(1); order[#order + 1] = "early" end)
    reactor.sleep(0)
    reactor.join(early)
    reactor.join(late)
    self:assert_equal({ "early", "late" }, order)
    self:assert_equal(5, math.floor(reactor.now()))
  end
  function C:test_cancel_while_sleeping()
    local finished = false
    reactor.scope(function(scope)
      scope:fork(function() reactor.sleep(1000); finished = true end)
      scope:cancel()
    end)
    self:assert_false(finished)
  end
  local summary = run({ C })
  self:assert_true(summary.ok, summary.results[1].message or summary.results[2].message)
end

function T:test_a_real_clock_case_after_a_virtual_one_keeps_the_real_clock()
  local V, R = hecate_test.Case("V"), hecate_test.Case("R")
  V.clock = "virtual"
  function V:test_x() reactor.sleep(100) end
  function R:test_x()
    local started = os.time()
    reactor.sleep(0.05)
    self:assert_true(os.time() - started < 2)
    self:assert_true(reactor.now() < 100, "the clock of the previous case leaked")
  end
  self:assert_true(run({ V, R }).ok)
end

function T:test_a_malformed_filter_pattern_is_refused_when_the_runner_is_made()
  self:assert_error(function() hecate_test.Runner({ filter = "[a" }) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.Runner({ filter = "%" }) end, { class = core.ArgumentError })
end

return require("hecate.core").finalise(T)
