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

local Reactor = reactor.Reactor
local AssertionFailure = failure.AssertionFailure

--- The outcome of one test.
---@class hecate.test.Result
---@field name string  full name, `Case.test_name`
---@field case string  name of the case
---@field status "passed"|"failed"|"errored"
---@field message? string  why the test failed or errored (may span several lines)
---@field location? string  `file:line` of the failed assertion
---@field differences? string[]  structural differences of a failed comparison
---@field traceback? string  traceback of an error that is not an assertion failure
---@field duration number  seconds of processor time

--- The totals of a run.
---@class hecate.test.Summary
---@field total integer
---@field passed integer
---@field failed integer
---@field errored integer
---@field ok boolean  true when every test passed
---@field results hecate.test.Result[]  in execution order
---@field duration number  seconds of processor time

--- Options of a runner.
---@class hecate.test.RunnerOptions
---@field reporter? hecate.test.Reporter  receives the progress of the run
---@field filter? string  Lua pattern: only tests whose full name matches are run

--- Receives the events of a run: `start(plan)`, `report(result)` once per test in execution order, `finish(summary)`.
---@class hecate.test.Reporter
---@field start fun(self: hecate.test.Reporter, plan: { total: integer })
---@field report fun(self: hecate.test.Reporter, result: hecate.test.Result)
---@field finish fun(self: hecate.test.Reporter, summary: hecate.test.Summary)

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
  self._reporter = options.reporter
  self._filter = options.filter
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

--- Runs `fn` in a reactor of its own, inside its own scope; `fn(scope)` returns an outcome (or
--- nothing). Returns the outcome with the failure of the reactor, or a leak, folded in.
---@param fn fun(scope: hecate.reactor.Scope): table?
---@return table outcome
local function in_reactor(fn)
  local rt = Reactor()
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
local function run_test(class, case_instance, name)
  local instance = core.allocate(class)
  for key, value in pairs(case_instance) do instance[key] = value end
  return in_reactor(function()
    if instance.set_up then
      local ok, err = xpcall(instance.set_up, capture, instance)
      if not ok then return classify(err, "set_up") end
    end
    local outcome = { status = "passed" }
    local ok, err = xpcall(class[name], capture, instance)
    if not ok then outcome = classify(err) end
    if instance.tear_down then
      local tok, terr = xpcall(instance.tear_down, capture, instance)
      if not tok and outcome.status == "passed" then outcome = classify(terr, "tear_down") end
    end
    return outcome
  end)
end

--- Lists the tests of `cases` that pass the filter, in order: `{ case, name, full_name }`.
---@param cases table[]  test cases
---@return { case: table, name: string, full_name: string }[] tests
function Runner:plan(cases)
  local tests = {}
  for _, class in ipairs(cases) do
    if not case_module.is_case(class) then
      error(core.ArgumentError("test.Runner: expects test cases created with test.Case, got " .. tostring(class)), 2)
    end
    core.finalise(class)
    for _, name in ipairs(case_module.test_names(class)) do
      local full_name = core.name(class) .. "." .. name
      if self._filter == nil or full_name:find(self._filter) then
        tests[#tests + 1] = { case = class, name = name, full_name = full_name }
      end
    end
  end
  return tests
end

--- Runs the tests of `cases` and returns the summary. The reporter, when given, is notified.
---
--- Raises `hecate.core.ArgumentError` when an element of `cases` is not a test case. Never
--- raises for a failing test.
---@param cases table[]  test cases created with `test.Case`
---@return hecate.test.Summary summary
function Runner:run(cases)
  local tests = self:plan(cases)
  local reporter = self._reporter
  local summary = { total = #tests, passed = 0, failed = 0, errored = 0, ok = true, results = {}, duration = 0 }
  if reporter then reporter:start({ total = #tests }) end
  local started = os.clock()

  local function record(test, outcome, duration)
    local result = {
      name = test.full_name, case = core.name(test.case), status = outcome.status, message = outcome.message,
      location = outcome.location, differences = outcome.differences, traceback = outcome.traceback,
      duration = duration,
    }
    summary.results[#summary.results + 1] = result
    summary[result.status] = summary[result.status] + 1
    if result.status ~= "passed" then summary.ok = false end
    if reporter then reporter:report(result) end
  end

  local index = 1
  while index <= #tests do
    local class = tests[index].case
    local last = index
    while tests[last + 1] and tests[last + 1].case == class do last = last + 1 end
    local case_instance = core.allocate(class)
    local setup_failure = run_hook(case_instance, "set_up_case", "set_up_case")
    local pending, durations = {}, {}
    for i = index, last do
      local clock = os.clock()
      local outcome
      if setup_failure then
        outcome = { status = "errored", message = setup_failure.message, traceback = setup_failure.traceback }
      else
        outcome = run_test(class, case_instance, tests[i].name)
      end
      pending[#pending + 1], durations[#durations + 1] = outcome, os.clock() - clock
    end
    if not setup_failure then
      local teardown_failure = run_hook(case_instance, "tear_down_case", "tear_down_case")
      -- reported on the last test of the case, so the plan stays exact
      if teardown_failure and pending[#pending].status == "passed" then pending[#pending] = teardown_failure end
    end
    for i = index, last do record(tests[i], pending[i - index + 1], durations[i - index + 1]) end
    index = last + 1
  end

  summary.duration = os.clock() - started
  if reporter then reporter:finish(summary) end
  return summary
end

return core.finalise(Runner)
