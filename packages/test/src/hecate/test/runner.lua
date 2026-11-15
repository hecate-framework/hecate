-- Runner: executes test cases, each test in a reactor of its own (testing.md, "Scope").
--   * A test runs in a new `Reactor`, inside a new scope: whatever it forks is cancelled when it
--     ends, and a test that leaves coroutines running fails ("leaked N coroutine(s)").
--   * Every raise is contained: a failing test never affects another test (invariant).
-- Outcomes follow the xUnit taxonomy (Meszaros 2007): passed, failed (an assertion did not
-- hold) and errored (anything else was raised, including a failure of set_up or tear_down).
global <const> type, xpcall, tostring, ipairs, pairs, require, os, debug, error, rawequal

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local case_module = require("hecate.test.case")
local failure = require("hecate.test.failure")
local assertions = require("hecate.test.assertions")
local discovery = require("hecate.test.discovery")

local Reactor = reactor.Reactor
local AssertionFailure = failure.AssertionFailure

--- The outcome of one test.
---@class hecate.test.Result
---@field name string  full name, `Case.test_name`
---@field case string  name of the case
---@field suite string  name of the suite the test belongs to
---@field status "passed"|"failed"|"errored"
---@field assertions integer  assertions the test called, passing or failing (those of `set_up_case` and `tear_down_case` are not counted)
---@field message? string  why the test failed or errored (may span several lines)
---@field location? string  `file:line` of the failed assertion
---@field differences? string[]  structural differences of a failed comparison
---@field traceback? string  traceback of an error that is not an assertion failure
---@field duration number  seconds of processor time

--- The totals of one suite.
---@class hecate.test.SuiteSummary
---@field name string
---@field total integer
---@field passed integer
---@field failed integer
---@field errored integer
---@field assertions integer
---@field duration number  seconds of processor time

--- The totals of a run.
---@class hecate.test.Summary
---@field total integer
---@field passed integer
---@field failed integer
---@field errored integer
---@field assertions integer
---@field ok boolean  true when every test passed
---@field exit_code integer  0 when `ok`, 1 otherwise: the status a command line runner exits with
---@field results hecate.test.Result[]  in execution order
---@field suites hecate.test.SuiteSummary[]  in execution order
---@field duration number  seconds of processor time

--- Options of a runner.
---@class hecate.test.RunnerOptions
---@field reporter? hecate.test.Reporter  receives the events of the run
---@field filter? string  Lua pattern: only tests whose full name matches are run
---@field clock? "real"|"virtual"  clock of the reactor of each test (default `"real"`); a case overrides it with its `clock` field. The virtual clock jumps to the next timer when nothing is ready, so sleeps and deadlines cost no time
---@field cases? string[]  only the cases with one of these names are run
---@field tags? string[]  only tests carrying at least one of these tags are run
---@field exclude_tags? string[]  tests carrying any of these tags are not run (wins over `tags`)

--- One event of a run, delivered to `Reporter:handle` as it happens. `type` is one of:
---
--- - `run_started`: `total` (tests), `suites` (count);
--- - `suite_started`: `suite` (name), `total` (tests of the suite);
--- - `test_started`: `suite`, `test` (full name), `index` (1-based within the suite);
--- - `test_finished`: `suite`, `test`, `index`, `result` (a `Result`);
--- - `suite_finished`: `suite`, `summary` (a `SuiteSummary`);
--- - `run_finished`: `summary` (a `Summary`).
---
--- The last test of a case finishes after `tear_down_case`, whose failure is reported on it.
---@class hecate.test.Event
---@field type "run_started"|"suite_started"|"test_started"|"test_finished"|"suite_finished"|"run_finished"
---@field total? integer
---@field suites? integer
---@field suite? string
---@field test? string
---@field index? integer
---@field result? hecate.test.Result
---@field summary? hecate.test.SuiteSummary|hecate.test.Summary

--- Consumes the events of a run, in order. Console, TAP and JSON-lines reporters implement it, and
--- so can the adapter of an IDE.
---@class hecate.test.Reporter
---@field handle fun(self: hecate.test.Reporter, event: hecate.test.Event)

--- Executes test cases and reports their results.
---@class hecate.test.Runner
---@overload fun(options?: hecate.test.RunnerOptions): hecate.test.Runner
local Runner = core.class("Runner")

--- Creates a runner.
---@param options? hecate.test.RunnerOptions
function Runner:init(options)
  options = options or {}
  if options.filter ~= nil and type(options.filter) ~= "string" then
    error(core.ArgumentError("test.Runner: filter must be a Lua pattern string, got " .. type(options.filter)), 2)
  end
  for _, key in ipairs({ "cases", "tags", "exclude_tags" }) do
    local list = options[key]
    if list ~= nil then
      if type(list) ~= "table" then
        error(core.ArgumentError("test.Runner: " .. key .. " must be a list of strings, got " .. type(list)), 2)
      end
      for _, tag in ipairs(list) do
        if type(tag) ~= "string" then
          error(core.ArgumentError("test.Runner: " .. key .. " must be a list of strings"), 2)
        end
      end
    end
  end
  if options.clock ~= nil and options.clock ~= "real" and options.clock ~= "virtual" then
    error(core.ArgumentError("test.Runner: clock must be \"real\" or \"virtual\""), 2)
  end
  self._clock = options.clock or "real"
  self._reporter = options.reporter
  self._filter = options.filter
  self._cases = options.cases
  self._tags = options.tags
  self._exclude_tags = options.exclude_tags
end

-- The tags of one test: those of its case (`tags`) and its own (`test_tags[name]`), as a set.
local function tags_of(class, name)
  local set = {}
  local function add(list) for _, tag in ipairs(list or {}) do set[tag] = true end end
  add(class.tags)
  if type(class.test_tags) == "table" then add(class.test_tags[name]) end
  return set
end

local function any_of(set, list)
  for _, tag in ipairs(list) do if set[tag] then return true end end
  return false
end

local LEAK = {} -- sentinel raised by the main computation of a test to cancel detached leaks

local function capture(err)
  if core.is_instance_of(err, AssertionFailure) then return { error = err } end
  return { error = err, traceback = debug.traceback(tostring(type(err) == "table" and err.message or err), 2) }
end

--- Turns a captured raise into the fields of an outcome.
---@param captured { error: any, traceback?: string }
---@param stage? string  prefix naming the step that raised ("set_up", "tear_down")
local function classify(captured, stage)
  local err = captured.error
  local outcome = {}
  if core.is_instance_of(err, AssertionFailure) then
    ---@cast err hecate.test.AssertionFailure
    outcome.status = "failed"
    outcome.message = err.message
    outcome.location = err.context.location
    outcome.differences = err.context.differences
  else
    outcome.status = "errored"
    if core.is_instance_of(err, core.Error) then
      outcome.message = ("%s: %s"):format(err.code, err.message)
    else
      outcome.message = tostring(err)
    end
    outcome.traceback = captured.traceback
    -- the body merely observed the cancellation that a failing forked computation caused
    outcome.cancelled = core.is_instance_of(err, core.CancellationError)
  end
  if stage then outcome.message = stage .. ": " .. outcome.message end
  return outcome
end

local clock_kind = "real" -- set by `Runner:run` for the case being run

--- Runs `fn` in a reactor of its own, inside its own scope; `fn(scope)` returns an outcome (or
--- nothing). Returns the outcome with the failure of the reactor, or a leak, folded in.
---@param fn fun(scope: hecate.reactor.Scope): table?
---@return table outcome
local function in_reactor(fn)
  local rt = Reactor({ clock = clock_kind })
  local outcome, leaked
  local ok, err = xpcall(rt.run, capture, rt, function()
    local scope_ok, scope_err = xpcall(reactor.scope, capture, function(scope)
      outcome = fn(scope)
      local live = scope:live()
      if live > 0 then
        leaked = live
        scope:cancel()
      end
    end)
    if not scope_ok then outcome = outcome or { status = "passed" }; outcome.scope_failure = scope_err end
    local detached = rt:live_coroutines() - 1 -- the main computation itself
    if detached > 0 then
      leaked = (leaked or 0) + detached
      error(LEAK, 0)
    end
  end)
  outcome = outcome or { status = "passed" }
  if outcome.scope_failure then
    -- a computation forked by the code failed after the code returned
    local folded = classify(outcome.scope_failure)
    if outcome.status == "passed" or outcome.cancelled then outcome = folded end
  end
  if not ok and not (type(err) == "table" and rawequal(err.error, LEAK)) and outcome.status == "passed" then
    outcome = classify(err)
  end
  if leaked and outcome.status == "passed" then
    outcome = { status = "failed", message = ("leaked %d coroutine(s): the test left them running"):format(leaked) }
  end
  return outcome
end

--- Runs a hook (`set_up_case`, ...) in its own reactor; returns nil, or the outcome that failed.
local function run_hook(instance, hook, stage)
  local fn = instance[hook]
  if fn == nil then return nil end
  local outcome = in_reactor(function()
    local ok, err = xpcall(fn, capture, instance)
    if not ok then return classify(err, stage) end
  end)
  if outcome.status ~= "passed" then return outcome end
  return nil
end

--- Runs one test on a fresh instance of `class`: set_up, the test, tear_down (when set_up
--- succeeded), each failure contained.
local function run_test(class, case_instance, name, arguments)
  local instance = core.allocate(class)
  for key, value in pairs(case_instance) do instance[key] = value end
  local counter = { assertions = 0 }
  assertions.count_into(counter)
  local outcome = in_reactor(function()
    if instance.set_up then
      local ok, err = xpcall(instance.set_up, capture, instance)
      if not ok then return classify(err, "set_up") end
    end
    local outcome = { status = "passed" }
    local ok, err = xpcall(class[name], capture, instance, arguments)
    if not ok then outcome = classify(err) end
    if instance.tear_down then
      local tok, terr = xpcall(instance.tear_down, capture, instance)
      if not tok and outcome.status == "passed" then outcome = classify(terr, "tear_down") end
    end
    return outcome
  end)
  assertions.count_into(nil)
  outcome.assertions = counter.assertions
  return outcome
end

--- Lists the tests of `cases` that pass the filter, in order: `{ case, name, full_name }`.
---@param cases table[]  test cases
---@return { case: table, name: string, full_name: string, suite: string, arguments?: any }[] tests
function Runner:plan(cases)
  local tests = {}
  for _, class in ipairs(cases) do
    if not case_module.is_case(class) then
      error(core.ArgumentError("test.Runner: expects test cases created with test.Case, got " .. tostring(class)), 2)
    end
    core.finalise(class)
    -- a suite is a test script: the file a case was loaded from, else the name of the case
    local suite = discovery.origin(class) or core.name(class)
    local wanted = self._cases == nil or any_of({ [core.name(class)] = true }, self._cases)
    for _, name in ipairs(wanted and case_module.test_names(class) or {}) do
      -- a parametrised test is one test per entry of `test_parameters[name]`
      local entries = type(class.test_parameters) == "table" and class.test_parameters[name] or nil
      if entries ~= nil and (type(entries) ~= "table" or #entries == 0) then
        error(core.ArgumentError(("test.Runner: test_parameters.%s of %s must be a non-empty list"):format(
          name, core.name(class))), 2)
      end
      local variants = { { full_name = core.name(class) .. "." .. name } }
      if entries then
        variants = {}
        local seen = {}
        for index, entry in ipairs(entries) do
          local label = type(entry) == "table" and type(entry.label) == "string" and entry.label or tostring(index)
          if seen[label] then
            error(core.ArgumentError(("test.Runner: test_parameters.%s of %s has the label '%s' twice"):format(
              name, core.name(class), label)), 2)
          end
          seen[label] = true
          variants[#variants + 1] = { full_name = ("%s.%s[%s]"):format(core.name(class), name, label), arguments = entry }
        end
      end
      for _, variant in ipairs(variants) do
        local full_name = variant.full_name
        local selected = self._filter == nil or full_name:find(self._filter)
        if selected and (self._tags or self._exclude_tags) then
          local set = tags_of(class, name)
          if self._tags and not any_of(set, self._tags) then selected = false end
          if self._exclude_tags and any_of(set, self._exclude_tags) then selected = false end
        end
        if selected then
          tests[#tests + 1] = { case = class, name = name, full_name = full_name, suite = suite, arguments = variant.arguments }
        end
      end
    end
  end
  return tests
end

--- Runs the tests of `cases` and returns the summary. The reporter, when given, receives the
--- events of the run (`hecate.test.Event`) as they happen.
---
--- Raises `hecate.core.ArgumentError` when an element of `cases` is not a test case. Never
--- raises for a failing test.
---@param cases table[]  test cases created with `test.Case`
---@return hecate.test.Summary summary
function Runner:run(cases)
  local tests = self:plan(cases)
  local reporter = self._reporter
  local summary = {
    total = #tests, passed = 0, failed = 0, errored = 0, assertions = 0, ok = true, exit_code = 0,
    results = {}, suites = {}, duration = 0,
  }
  local function emit(event) if reporter then reporter:handle(event) end end
  local started = os.clock()

  local suite_count = 0
  for i, test in ipairs(tests) do
    if i == 1 or tests[i - 1].suite ~= test.suite then suite_count = suite_count + 1 end
  end
  emit({ type = "run_started", total = #tests, suites = suite_count })

  local first = 1
  while first <= #tests do
    local suite_name = tests[first].suite
    local last = first
    while tests[last + 1] and tests[last + 1].suite == suite_name do last = last + 1 end
    local suite = {
      name = suite_name, total = last - first + 1, passed = 0, failed = 0, errored = 0, assertions = 0, duration = 0,
    }
    summary.suites[#summary.suites + 1] = suite
    emit({ type = "suite_started", suite = suite_name, total = suite.total })
    local suite_clock = os.clock()

    local function finish(position, test, outcome, duration)
      local result = {
        name = test.full_name, case = core.name(test.case), suite = suite_name, status = outcome.status,
        assertions = outcome.assertions or 0, message = outcome.message, location = outcome.location,
        differences = outcome.differences, traceback = outcome.traceback, duration = duration,
      }
      summary.results[#summary.results + 1] = result
      summary[result.status] = summary[result.status] + 1
      suite[result.status] = suite[result.status] + 1
      summary.assertions = summary.assertions + result.assertions
      suite.assertions = suite.assertions + result.assertions
      if result.status ~= "passed" then summary.ok, summary.exit_code = false, 1 end
      emit({ type = "test_finished", suite = suite_name, test = test.full_name, index = position, result = result })
    end

    local index = first
    while index <= last do
      local class = tests[index].case
      local end_of_case = index
      while end_of_case + 1 <= last and tests[end_of_case + 1].case == class do end_of_case = end_of_case + 1 end
      local case_instance = core.allocate(class)
      clock_kind = class.clock or self._clock
      local setup_failure = run_hook(case_instance, "set_up_case", "set_up_case")
      for i = index, end_of_case do
        local position = i - first + 1
        emit({ type = "test_started", suite = suite_name, test = tests[i].full_name, index = position })
        local clock = os.clock()
        local outcome
        if setup_failure then
          outcome = { status = "errored", message = setup_failure.message, traceback = setup_failure.traceback }
        else
          outcome = run_test(class, case_instance, tests[i].name, tests[i].arguments)
        end
        local duration = os.clock() - clock
        if i < end_of_case then
          finish(position, tests[i], outcome, duration)
        else
          -- the last test of the case finishes after tear_down_case, whose failure it reports (plan stays exact)
          if not setup_failure then
            local teardown_failure = run_hook(case_instance, "tear_down_case", "tear_down_case")
            if teardown_failure and outcome.status == "passed" then
              teardown_failure.assertions = outcome.assertions
              outcome = teardown_failure
            end
          end
          finish(position, tests[i], outcome, os.clock() - clock)
        end
      end
      index = end_of_case + 1
    end

    suite.duration = os.clock() - suite_clock
    emit({ type = "suite_finished", suite = suite_name, summary = suite })
    first = last + 1
  end

  summary.duration = os.clock() - started
  clock_kind = "real"
  emit({ type = "run_finished", summary = summary })
  return summary
end

return core.finalise(Runner)
