local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("ErrorTest")

--- Passes a value through untyped, so that a test can give an argument that is invalid on purpose.
---@param value any
---@return any
local function invalid(value) return value end

function T:set_up() core.set_debug_mode(false) end
function T:tear_down() core.set_debug_mode(false) end

function T:test_constructed_from_a_message()
  local e = core.Error("something failed")
  self:assert_equal("something failed", e.message)
  self:assert_equal("hecate.core.Error", e.code)
  self:assert_equal("table", type(e.context))
  self:assert_nil(e.cause)
  self:assert_nil(e.traceback)
end

function T:test_constructed_from_fields_with_table_call_syntax()
  local cause = core.Error("low level")
  local e = core.ConfigurationError { message = "bad port", cause = cause, context = { port = 70000 } }
  self:assert_equal("bad port", e.message)
  self:assert_true(e.cause == cause)
  self:assert_equal(70000, e.context.port)
  self:assert_equal("hecate.core.ConfigurationError", e.code)
end

function T:test_message_with_extra_fields()
  local e = core.Error("m", { context = { k = 1 } })
  self:assert_equal("m", e.message)
  self:assert_equal(1, e.context.k)
end

function T:test_message_defaults_to_class_name()
  self:assert_equal("ValidationError", core.ValidationError().message)
end

function T:test_hierarchy()
  for _, name in ipairs({
    "ConfigurationError", "ConformanceError", "ArgumentError", "CancellationError",
    "DeadlineExceededError", "NonYieldableContextError", "ClosedChannelError", "NetworkError", "IoError", "ProtocolError", "ValidationError", "DatabaseError",
  }) do
    local class = core[name]
    self:assert_true(core.superclass(class) == core.Error, name)
    self:assert_equal("hecate.core." .. name, class.code)
    self:assert_true(core.is_instance_of(class("x"), core.Error))
  end
end

function T:test_io_error_is_a_base_class_for_file_system_failures()
  local Derived = core.error_class("DerivedIoError", "test.DerivedIoError", core.IoError)
  self:assert_true(core.is_instance_of(Derived("x"), core.IoError))
  self:assert_false(core.is_instance_of(core.IoError("x"), core.NetworkError))
end

function T:test_database_error_carries_sqlstate()
  local e = core.DatabaseError { message = "duplicate", sqlstate = "23505" }
  self:assert_equal("23505", e.sqlstate)
  self:assert_equal("23505", core.DatabaseError("m", { sqlstate = "23505" }).sqlstate)
  self:assert_nil(core.DatabaseError("m").sqlstate)
end

function T:test_error_class_helper_defines_stable_code()
  local FieldTooLargeError = core.error_class("FieldTooLargeError", "hecate.http.FieldTooLargeError", core.ProtocolError)
  local e = FieldTooLargeError("field too large")
  self:assert_equal("hecate.http.FieldTooLargeError", e.code)
  self:assert_true(core.is_instance_of(e, core.ProtocolError))
  self:assert_true(core.is_instance_of(e, core.Error))
end

function T:test_instance_code_override()
  self:assert_equal("custom.code", core.Error { message = "m", code = "custom.code" }.code)
end

function T:test_tostring_renders_chain()
  local root = core.NetworkError("connection refused")
  local mid = core.ProtocolError { message = "handshake failed", cause = root }
  local top = core.Error { message = "request failed", cause = mid }
  self:assert_equal(
    "hecate.core.Error: request failed\n"
      .. "caused by: hecate.core.ProtocolError: handshake failed\n"
      .. "caused by: hecate.core.NetworkError: connection refused",
    tostring(top))
  self:assert_true(top:root_cause() == root)
end

function T:test_tostring_with_foreign_cause()
  local e = core.Error { message = "wrapped", cause = "plain string" }
  self:assert_equal("hecate.core.Error: wrapped\ncaused by: plain string", tostring(e))
  self:assert_equal("plain string", e:root_cause())
end

function T:test_tostring_terminates_on_cyclic_chain()
  local a = core.Error("a")
  local b = core.Error { message = "b", cause = a }
  a.cause = b
  self:assert_equal("string", type(tostring(a)))
  self:assert_not_nil(a:root_cause())
end

function T:test_traceback_captured_only_in_debug_mode()
  self:assert_nil(core.Error("x").traceback)
  core.set_debug_mode(true)
  self:assert_true(core.is_debug_mode())
  local tb = core.Error("x").traceback or ""
  self:assert_equal("string", type(tb))
  self:assert_true(tb:find("stack traceback", 1, true) ~= nil)
end

function T:test_raised_error_object_is_caught_intact()
  local e = core.ValidationError { message = "invalid port", context = { field = "port" } }
  local ok, caught = pcall(error, e)
  self:assert_false(ok)
  self:assert_true(caught == e)
  self:assert_equal("port", caught and caught.context and caught.context.field)
end

function T:test_message_must_be_a_string()
  for _, fields in ipairs({ invalid({ message = 42 }), invalid({ message = {} }), invalid({ message = true }) }) do
    local err = self:assert_error(function() return core.Error(fields) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
    self:assert_true(err.message:find("message must be a string", 1, true) ~= nil)
  end
  local err = self:assert_error(function() return core.Error(invalid(42)) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_traceback_starts_at_the_caller_not_inside_the_library()
  core.set_debug_mode(true)
  for _, make in ipairs({
    function() return core.Error("x") end,
    function() return core.ValidationError { message = "x" } end,
    function() return core.DatabaseError("x", { sqlstate = "23505" }) end,
  }) do
    local tb = make().traceback or ""
    local first = tb:match("stack traceback:\n\t([^\n]*)") or ""
    self:assert_true(first:find("error_test.lua", 1, true) ~= nil, first)
  end
end

function T:test_error_class_validates_name_code_and_superclass()
  for _, args in ipairs({ { "", "x.Code" }, { "Name", "" }, { 42, "x.Code" }, { "Name", 42 } }) do
    local err = self:assert_error(function() core.error_class(invalid(args[1]), invalid(args[2])) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
    self:assert_true(err.message:find("must be a non-empty string", 1, true) ~= nil)
  end
  local Plain = core.class("Plain")
  core.finalise(Plain)
  local err = self:assert_error(function() core.error_class("Name", "x.Code", Plain) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

return T
