local test = require("harness.test")
local core = require("hecate.core")
local chain = require("hecate.kernel.chain")
local T = test.Case("ChainTest")

--- Passes a value through untyped, so that a test can give an argument that is invalid on purpose.
---@param value any
---@return any
local function invalid(value) return value end

--- A filter that records its name before and after the rest of the chain.
local function recorder(trace, name)
  return {
    handle = function(_, request, next)
      trace[#trace + 1] = name .. ":in"
      local result = next(request)
      trace[#trace + 1] = name .. ":out"
      return result
    end,
  }
end

function T:test_empty_list_returns_the_action_itself()
  local function action(request) return request end
  self:assert_true(chain.compose({}, action) == action)
end

function T:test_filters_run_outermost_first_in_the_order_given()
  local trace = {}
  local run = chain.compose({ recorder(trace, "a"), recorder(trace, "b") }, function()
    trace[#trace + 1] = "action"
    return "ok"
  end)
  self:assert_equal("ok", run({}))
  self:assert_equal("a:in b:in action b:out a:out", table.concat(trace, " "))
end

function T:test_filter_can_short_circuit()
  local called = false
  local gate = { handle = function() return "denied" end }
  local run = chain.compose({ gate }, function() called = true end)
  self:assert_equal("denied", run({}))
  self:assert_false(called)
end

function T:test_filter_can_transform_the_request()
  local filter = { handle = function(_, request, next) return next({ id = request.id + 1 }) end }
  local run = chain.compose({ filter }, function(request) return request.id end)
  self:assert_equal(2, run({ id = 1 }))
end

function T:test_filter_can_post_process_the_result()
  local filter = { handle = function(_, request, next) return next(request) .. "!" end }
  local run = chain.compose({ filter }, function() return "hi" end)
  self:assert_equal("hi!", run({}))
end

function T:test_filter_is_called_as_a_method_of_itself()
  local seen
  local filter = { handle = function(self_, request, next) seen = self_; return next(request) end }
  chain.compose({ filter }, function() end)({})
  self:assert_true(seen == filter)
end

function T:test_class_instances_are_filters()
  local Tag = core.class("Tag")
  function Tag:handle(request, next) return "tag:" .. next(request) end
  core.finalise(Tag)
  local run = chain.compose({ Tag() }, function() return "x" end)
  self:assert_equal("tag:x", run({}))
end

function T:test_error_of_a_filter_propagates_unchanged()
  local failure = core.Error("boom")
  local filter = { handle = function() error(failure, 0) end }
  local run = chain.compose({ filter }, function() end)
  self:assert_true(self:assert_error(function() run({}) end) == failure)
end

function T:test_error_of_the_action_propagates_through_filters()
  local failure = core.Error("boom")
  local run = chain.compose({ recorder({}, "a") }, function() error(failure, 0) end)
  self:assert_true(self:assert_error(function() run({}) end) == failure)
end

function T:test_non_filter_raises_argument_error_at_composition()
  local err = self:assert_error(function()
    chain.compose({ recorder({}, "a"), invalid({}) }, function() end)
  end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  self:assert_equal(2, err.context.index)
  self:assert_error(function() chain.compose({ invalid(42) }, function() end) end)
  self:assert_error(function() chain.compose({ invalid(function() end) }, function() end) end)
end

function T:test_invalid_arguments_raise_argument_error()
  local err = self:assert_error(function() chain.compose({}, invalid(nil)) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  err = self:assert_error(function() chain.compose(invalid(nil), function() end) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_composition_snapshots_the_list()
  local trace = {}
  local filters = { recorder(trace, "a") }
  local run = chain.compose(filters, function() end)
  filters[#filters + 1] = recorder(trace, "late")
  run({})
  self:assert_equal("a:in a:out", table.concat(trace, " "))
end

function T:test_filter_may_call_next_more_than_once()
  local count = 0
  local retry = { handle = function(_, request, next) next(request); return next(request) end }
  chain.compose({ retry }, function() count = count + 1 end)({})
  self:assert_equal(2, count)
end

function T:test_multiple_results_pass_through()
  local pass = { handle = function(_, request, next) return next(request) end }
  local a, b = chain.compose({ pass }, function() return 1, 2 end)({})
  self:assert_equal(1, a)
  self:assert_equal(2, b)
end

function T:test_is_filter()
  self:assert_true(chain.is_filter({ handle = function() end }))
  self:assert_false(chain.is_filter({}))
  self:assert_false(chain.is_filter(nil))
end

return T
