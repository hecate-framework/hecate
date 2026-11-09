---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("DefaultLoggerTest")

function T:teardown() log.set_default(nil) end

function T:test_default_is_one_shared_logger_at_informational()
  local a = log.default()
  self:assert_true(a == log.default())
  self:assert_true(a:severity() == log.Severity.informational)
  self:assert_true(a:is_enabled(log.Severity.error))
  self:assert_false(a:is_enabled(log.Severity.debug))
end

function T:test_set_default_replaces_it_and_nil_restores_the_lazy_one()
  local mine = log.Logger({ name = "mine" })
  log.set_default(mine)
  self:assert_true(log.default() == mine)
  log.set_default(nil)
  self:assert_false(log.default() == mine)
end

function T:test_set_default_refuses_a_value_without_log_methods()
  self:assert_error(function() log.set_default({}) end)
end

return T
