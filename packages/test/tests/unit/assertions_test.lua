local core = require("hecate.core")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("AssertionsTest")

-- Raises the failure of `fn`, or fails when `fn` does not fail.
local function failure_of(self, fn)
  local ok, err = pcall(fn)
  self:assert_false(ok, "expected the assertion to fail")
  self:assert_true(core.is_instance_of(err, hecate_test.AssertionFailure), tostring(err))
  return err
end

-- The cases below are self-hosted by the bootstrap harness only for the framework's own tests;
-- the class under test is a hecate.test.Case instance.
local subject
local function new_case()
  local class = hecate_test.Case("Subject")
  core.finalise(class)
  return core.allocate(class)
end
subject = new_case()

function T:test_assert_true_and_false()
  subject:assert_true(1)
  subject:assert_false(nil)
  failure_of(self, function() subject:assert_true(false) end)
  failure_of(self, function() subject:assert_false(0) end)
end

function T:test_assert_nil_and_not_nil()
  subject:assert_nil(nil)
  subject:assert_not_nil(false)
  failure_of(self, function() subject:assert_nil(1) end)
  failure_of(self, function() subject:assert_not_nil(nil) end)
end

function T:test_assert_equal_compares_primitives_by_value()
  subject:assert_equal("a", "a")
  subject:assert_equal(1, 1.0)
  local err = failure_of(self, function() subject:assert_equal("a", "b") end)
  self:assert_equal('expected "a", got "b"', err.message)
end

function T:test_assert_equal_compares_tables_structurally_with_a_diff()
  subject:assert_equal({ 1, { x = true } }, { 1, { x = true } })
  local err = failure_of(self, function() subject:assert_equal({ a = 1, b = { 2 } }, { a = 1, b = { 3 } }) end)
  self:assert_equal("tables differ:\n  .b[1]: expected 2, got 3", err.message)
  self:assert_equal(".b[1]: expected 2, got 3", err.context.differences[1])
end

function T:test_a_custom_message_prefixes_the_description()
  local err = failure_of(self, function() subject:assert_equal(1, 2, "counting") end)
  self:assert_equal("counting\nexpected 1, got 2", err.message)
  local err2 = failure_of(self, function() subject:assert_true(false, "only this") end)
  self:assert_equal("only this", err2.message)
end

function T:test_the_failure_records_the_location_of_the_assertion_in_the_test()
  local err = failure_of(self, function() subject:assert_true(false) end)
  self:assert_match("assertions_test%.lua:%d+$", err.context.location)
end

function T:test_assert_not_equal_and_assert_same()
  subject:assert_not_equal({ 1 }, { 2 })
  failure_of(self, function() subject:assert_not_equal({ 1 }, { 1 }) end)
  local t = {}
  subject:assert_same(t, t)
  failure_of(self, function() subject:assert_same({}, {}) end)
end

function T:test_assert_near_uses_an_absolute_tolerance()
  subject:assert_near(0.3, 0.1 + 0.2)
  subject:assert_near(100, 101, 2)
  failure_of(self, function() subject:assert_near(1, 1.5, 0.1) end)
  failure_of(self, function() subject:assert_near(1, "1") end)
end

function T:test_assert_match_uses_lua_patterns()
  subject:assert_match("^he", "hello")
  failure_of(self, function() subject:assert_match("^lo", "hello") end)
  failure_of(self, function() subject:assert_match("x", 1) end)
end

function T:test_assert_error_returns_the_raised_value_and_matches_a_pattern()
  local err = subject:assert_error(function() error("boom", 0) end, "^bo")
  self:assert_equal("boom", err)
  failure_of(self, function() subject:assert_error(function() end) end)
  failure_of(self, function() subject:assert_error(function() error("boom", 0) end, "^zz") end)
end

function T:test_assert_error_checks_class_and_code()
  local fn = function() error(core.ArgumentError("bad input"), 0) end
  subject:assert_error(fn, { class = core.ArgumentError })
  subject:assert_error(fn, { class = core.PreconditionError, code = "hecate.core.ArgumentError", pattern = "^bad" })
  failure_of(self, function() subject:assert_error(fn, { class = core.StateError }) end)
  failure_of(self, function() subject:assert_error(fn, { code = "other" }) end)
  failure_of(self, function() subject:assert_error(fn, { message = "bad" }) end)
  subject:assert_error(fn, { message = "bad input" })
end

function T:test_assert_shape_checks_predicates_nested_tables_and_literals()
  local value = { id = 7, name = "x", tags = { "a" }, extra = true }
  subject:assert_shape({ id = hecate_test.of_type("number"), name = "x", tags = { [1] = "a" } }, value)
  local err = failure_of(self, function()
    subject:assert_shape({ id = hecate_test.of_type("string"), name = "y", missing = { a = 1 } }, value)
  end)
  self:assert_match("%.id: 7 does not satisfy the predicate", err.message)
  self:assert_match('%.name: expected "y", got "x"', err.message)
  self:assert_match("%.missing: expected a table, got nil", err.message)
end

function T:test_fail_always_fails()
  local err = failure_of(self, function() subject:fail() end)
  self:assert_equal("failed", err.message)
  self:assert_equal("why", failure_of(self, function() subject:fail("why") end).message)
end

return require("hecate.core").finalise(T)
