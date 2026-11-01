local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")

local T = test.Case("UnobservedFailureTest")

--- Runs `fn` on a virtual reactor with the hook installed; returns the reports.
local function run(hook_options, fn)
  local reports = {}
  local options = { clock = "virtual" }
  options.on_unobserved_failure = hook_options or function(err, future) reports[#reports + 1] = { err = err, future = future } end
  reactor.Reactor(options):run(fn)
  return reports
end

function T:test_unwaited_detached_failure_is_reported_once()
  local future
  local reports = run(nil, function()
    future = reactor.detach(function() error(core.Error("boom")) end)
    reactor.sleep(1)
  end)
  self:assert_equal(1, #reports)
  self:assert_equal("boom", reports[1].err.message)
  self:assert_true(reports[1].future == future)
end

function T:test_failure_with_a_waiter_is_observed()
  local reports = run(nil, function()
    local future = reactor.detach(function() reactor.sleep(1); error(core.Error("boom")) end)
    self:assert_error(function() future:value() end)
  end)
  self:assert_equal(0, #reports)
end

function T:test_cancelled_and_completed_detached_computations_are_not_reported()
  local reports = run(nil, function()
    reactor.detach(function() return 1 end)
    reactor.detach(function() reactor.sleep(10) end):cancel()
    reactor.sleep(1)
  end)
  self:assert_equal(0, #reports)
end

function T:test_forked_failures_are_not_reported()
  local reports = {}
  local err = self:assert_error(function()
    reactor.Reactor({ clock = "virtual", on_unobserved_failure = function(e) reports[#reports + 1] = e end }):run(function()
      reactor.fork(function() error(core.Error("boom")) end)
      reactor.sleep(1)
    end)
  end)
  self:assert_equal("boom", err.message)
  self:assert_equal(0, #reports)
end

function T:test_a_failing_hook_does_not_stop_the_reactor()
  local survived = false
  run(function() error("hook failure") end, function()
    reactor.detach(function() error(core.Error("boom")) end)
    reactor.sleep(1)
    survived = true
  end)
  self:assert_true(survived)
end

function T:test_hook_must_be_a_function()
  ---@diagnostic disable-next-line: assign-type-mismatch  -- the option is invalid on purpose
  local err = self:assert_error(function() reactor.Reactor({ on_unobserved_failure = 3 }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_without_a_hook_the_failure_stays_silent()
  reactor.Reactor({ clock = "virtual" }):run(function()
    reactor.detach(function() error(core.Error("boom")) end)
    reactor.sleep(1)
  end)
end

return T
