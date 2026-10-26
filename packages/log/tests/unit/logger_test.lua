local test = require("harness.test")
local core = require("hecate.core")
local log = require("hecate.log")
local Severity = log.Severity
local T = test.Case("LoggerTest")

local function new_logger(options)
  local sink = log.MemorySink()
  options = options or {}
  options.sinks = { sink }
  options.clock = options.clock or function() return 1000 end
  return log.Logger(options), sink
end

function T:test_every_severity_has_a_method_that_records_that_severity()
  local logger, sink = new_logger({ severity = "debug" })
  for _, name in ipairs(Severity:names()) do logger[name](logger, "message " .. name) end
  local records = sink:records()
  self:assert_equal(8, #records)
  for i, name in ipairs(Severity:names()) do
    self:assert_true(records[i].severity == Severity[name])
    self:assert_equal("message " .. name, records[i].message)
  end
end

function T:test_the_default_severity_is_informational()
  local logger, sink = new_logger()
  logger:debug("hidden")
  logger:informational("shown")
  self:assert_equal(1, #sink:records())
  self:assert_equal("shown", sink:records()[1].message)
end

function T:test_a_disabled_severity_builds_no_record_and_reaches_no_sink()
  local logger, sink = new_logger({ severity = "error" })
  logger:warning("hidden")
  self:assert_false(logger:is_enabled(Severity.warning))
  self:assert_true(logger:is_enabled("critical"))
  self:assert_equal(0, #sink:records())
end

function T:test_errors_name_the_call_the_caller_wrote()
  local logger = new_logger()
  local err = self:assert_error(function() logger:set_severity("verbose") end)
  self:assert_true(err.message:find("^log%.Logger%.set_severity: invalid severity") ~= nil)
  err = self:assert_error(function() logger:is_enabled("verbose") end)
  self:assert_true(err.message:find("^log%.Logger%.is_enabled: invalid severity") ~= nil)
  err = self:assert_error(function() logger:informational(12) end)
  self:assert_true(err.message:find("^log%.Logger%.informational: message must be a string") ~= nil)
  err = self:assert_error(function() logger:log("warning", 12) end)
  self:assert_true(err.message:find("^log%.Logger%.log: message must be a string") ~= nil)
end

function T:test_set_severity_accepts_a_name_or_a_severity()
  local logger = new_logger()
  logger:set_severity("debug")
  self:assert_true(logger:is_enabled(Severity.debug))
  logger:set_severity(Severity.alert)
  self:assert_true(logger:severity() == Severity.alert)
  self:assert_false(logger:is_enabled(Severity.error))
end

function T:test_an_unknown_severity_is_an_argument_error()
  local logger = new_logger()
  local err = self:assert_error(function() logger:set_severity("verbose") end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  self:assert_error(function() log.Logger({ severity = "verbose" }) end)
  self:assert_error(function() logger:log("verbose", "x") end)
end

function T:test_the_record_carries_message_fields_timestamp_and_name()
  local logger, sink = new_logger({ name = "app", clock = function() return 42 end })
  logger:error("failed", { code = 7 })
  local record = sink:records()[1]
  self:assert_equal("failed", record.message)
  self:assert_equal(7, record.fields.code)
  self:assert_equal(42, record.timestamp)
  self:assert_equal("app", record.logger)
end

function T:test_context_of_a_child_logger_is_merged_over_its_parent()
  local logger, sink = new_logger({ context = { service = "api", request_id = "a" } })
  local child = logger:with_context({ request_id = "b", user = "u" })
  child:informational("hi")
  logger:informational("parent")
  local context = sink:records()[1].context
  self:assert_equal("api", context.service)
  self:assert_equal("b", context.request_id)
  self:assert_equal("u", context.user)
  self:assert_equal("a", sink:records()[2].context.request_id)
end

function T:test_a_child_shares_the_sinks_of_its_parent()
  local logger, sink = new_logger()
  local late = log.MemorySink()
  local child = logger:with_context({ a = 1 })
  logger:add_sink(late)
  child:informational("x")
  self:assert_equal(1, #sink:records())
  self:assert_equal(1, #late:records())
end

function T:test_the_context_provider_supplies_the_ambient_context()
  local ambient = { request_id = "r1", service = "ambient" }
  local logger, sink = new_logger({
    context = { service = "static" }, context_provider = function() return ambient end,
  })
  logger:informational("x")
  local context = sink:records()[1].context
  self:assert_equal("r1", context.request_id)
  self:assert_equal("static", context.service)
  self:assert_equal("ambient", ambient.service)
end

function T:test_a_failing_sink_never_fails_the_caller_and_is_counted()
  local logger, sink = new_logger()
  logger:add_sink({ write = function() error("disk full") end })
  logger:informational("x")
  self:assert_equal(1, #sink:records())
  self:assert_equal(1, logger:failures())
end

function T:test_a_sink_without_write_is_rejected()
  local logger = new_logger()
  self:assert_error(function() logger:add_sink({}) end)
  self:assert_error(function() log.Logger({ sinks = { 3 } }) end)
end

function T:test_message_and_fields_are_checked()
  local logger = new_logger()
  self:assert_error(function() logger:informational(12) end)
  self:assert_error(function() logger:informational("x", "y") end)
end

function T:test_redact_wraps_named_fields_at_any_depth_without_touching_the_caller_table()
  local logger, sink = new_logger({ redact = { "Password", "token" } })
  local fields = { user = "ada", password = "p", nested = { Token = "t", ok = 1 } }
  logger:informational("login", fields)
  local record = sink:records()[1]
  self:assert_equal("p", fields.password)
  self:assert_equal("ada", record.fields.user)
  self:assert_equal("p", record.fields.password:reveal())
  self:assert_equal("t", record.fields.nested.Token:reveal())
  self:assert_equal(1, record.fields.nested.ok)
end

function T:test_redact_applies_to_the_context_and_is_inherited_by_children()
  local logger, sink = new_logger({ redact = { "secret" } })
  logger:with_context({ secret = "s" }):informational("x")
  self:assert_equal("s", sink:records()[1].context.secret:reveal())
end

function T:test_redact_rejects_a_value_that_is_not_a_list_of_names()
  self:assert_error(function() log.Logger({ redact = "password" }) end)
  self:assert_error(function() log.Logger({ redact = { 1 } }) end)
end

function T:test_a_context_provider_that_raises_or_returns_a_non_table_is_counted_and_the_record_kept()
  local logger, sink = new_logger({ context_provider = function() error("no scope") end })
  logger:informational("x")
  self:assert_equal(1, #sink:records())
  self:assert_equal(1, logger:failures())
  local other, memory = new_logger({ context_provider = function() return "oops" end })
  other:informational("y")
  self:assert_equal(1, #memory:records())
  self:assert_equal(1, other:failures())
end

return T
