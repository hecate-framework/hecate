local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local support = {
  run_virtual = function(fn, ...) return reactor.Reactor({ clock = "virtual" }):run(fn, ...) end,
}
local T = test.Case("NonYieldableTest")

local function is_non_yieldable(err) return core.is_instance_of(err, core.NonYieldableContextError) end

function T:test_suspending_operations_raise_outside_a_running_reactor()
  for name, call in pairs({
    sleep = function() reactor.sleep(1) end,
    fork = function() reactor.fork(function() end) end,
    scope = function() reactor.scope(function() end) end,
    deadline = function() reactor.deadline(1, function() end) end,
    join = function() reactor.join() end,
  }) do
    local err = self:assert_error(call)
    self:assert_true(is_non_yieldable(err), name)
  end
end

function T:test_suspending_from_an_unmanaged_coroutine_raises_immediately()
  support.run_virtual(function()
    local co = coroutine.create(function() reactor.sleep(1) end)
    local ok, err = coroutine.resume(co)
    self:assert_false(ok)
    self:assert_true(is_non_yieldable(err))
  end)
end

function T:test_table_sort_comparator_is_detected()
  support.run_virtual(function()
    local err = self:assert_error(function()
      table.sort({ 3, 2, 1 }, function(a, b) reactor.sleep(0); return a < b end)
    end)
    self:assert_true(is_non_yieldable(err))
    self:assert_true(err.message:find("non%-yieldable") ~= nil)
  end)
end

function T:test_string_gsub_callback_is_detected()
  support.run_virtual(function()
    local err = self:assert_error(function()
      return ("abc"):gsub(".", function() reactor.sleep(0) end)
    end)
    self:assert_true(is_non_yieldable(err))
  end)
end

function T:test_raw_yield_in_a_managed_coroutine_fails_the_future()
  local err = self:assert_error(function()
    support.run_virtual(function() reactor.fork(function() coroutine.yield("raw") end) end)
  end)
  self:assert_true(core.is_instance_of(err, core.Error))
  self:assert_true(err.message:find("coroutine.yield", 1, true) ~= nil)
end

function T:test_the_reactor_remains_usable_after_the_detection()
  local value = support.run_virtual(function()
    pcall(table.sort, { 2, 1 }, function() reactor.sleep(0); return true end)
    reactor.sleep(1)
    return "fine"
  end)
  self:assert_equal("fine", value)
end

return T
