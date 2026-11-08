---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- Diagnostics, unknown keys and option checks (configuration.md, "Validation" and "Errors and messages").
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigErrorsTest")

function T:test_unknown_key_is_an_error_with_its_file()
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { databse = { port = 1 } }" } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  local violation = err.context.violations[1]
  self:assert_equal("/databse", violation.path)
  self:assert_equal("additional_properties", violation.code)
  self:assert_equal("config/default.lua", violation.source)
end

function T:test_unknown_key_is_an_error_at_every_depth()
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { database = { prot = 1 } }" } })
  self:assert_equal("/database/prot", err.context.violations[1].path)
  local err2 = fixture.failure({ files = { ["config/default.lua"] = "return { logging = { sinks = {}, extra = 1 } }" } })
  self:assert_equal("/logging/extra", err2.context.violations[1].path)
end

function T:test_every_problem_is_reported_at_once()
  local err = fixture.failure({
    files = { ["config/default.lua"] = "return { nme = 'x', database = { port = 'text' } }" },
    env = { HECATE_DATABASE__HOST = "ok", HECATE_LIMITS__MAX_DEPTH = "0" },
  })
  self:assert_true(#err.context.violations >= 3)
  local text = tostring(err)
  self:assert_true(text:find("invalid configuration (", 1, true) ~= nil)
  self:assert_true(text:find("/nme", 1, true) ~= nil)
  self:assert_true(text:find("/database/port", 1, true) ~= nil)
  self:assert_true(text:find("/limits/max_depth", 1, true) ~= nil)
end

function T:test_message_names_path_code_and_source()
  local err = fixture.failure({ env = { HECATE_DATABASE__PORT = "abc" } })
  local text = tostring(err)
  self:assert_true(text:find("config.load: invalid configuration (1 problem, environment development)", 1, true) ~= nil, text)
  self:assert_true(text:find("/database/port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)", 1, true) ~= nil, text)
end

function T:test_missing_required_key()
  local err = fixture.failure({ options = { properties = { token = schema.string() } } })
  local violation = err.context.violations[1]
  self:assert_equal("/token", violation.path)
  self:assert_equal("required", violation.code)
  self:assert_equal("-", violation.source)
end

function T:test_wrong_type_in_a_file()
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { database = { port = '5432' } }" } })
  self:assert_equal("type", err.context.violations[1].code)
  self:assert_equal("config/default.lua", err.context.violations[1].source)
end

function T:test_file_failures_name_the_file()
  local cases = {
    "return {",
    "error('boom')",
    "return 42",
    "return require('os')",
    "return os.getenv('HOME')",
  }
  for _, source in ipairs(cases) do
    local err = fixture.failure({ files = { ["config/default.lua"] = source } })
    self:assert_equal("hecate.core.ConfigurationError", err.code, source)
    self:assert_equal("config/default.lua", err.context.file, source)
  end
end

function T:test_unreadable_file_is_an_error()
  local err = fixture.failure({ options = { read_file = function() return nil, "permission denied" end } })
  self:assert_equal("config/default.lua", err.context.file)
  self:assert_true(tostring(err):find("permission denied", 1, true) ~= nil)
end

function T:test_cyclic_layer_is_an_error_not_a_crash()
  local err = fixture.failure({ files = { ["config/default.lua"] = "local t = {} t.a = t return t" } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
end

function T:test_cross_key_rule_for_the_file_sink()
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { logging = { sinks = { 'file' } } }" } })
  self:assert_equal("/logging/file/path", err.context.violations[1].path)
  self:assert_equal("required", err.context.violations[1].code)
end

function T:test_option_checks()
  local function refused(options, pattern)
    self:assert_error(function() fixture.load({ options = options }) end, pattern)
  end
  refused({ unknown = 1 }, "unknown")
  refused({ properties = 1 }, "properties")
  refused({ properties = { a = 1 } }, "properties")
  refused({ properties = { logging = schema.string() } }, "logging")
  refused({ properties = { limits = schema.string() } }, "limits")
  refused({ secrets = { "database.nope" } }, "database.nope")
  refused({ secrets = { "database" } }, "database")
  refused({ getenv = 1 }, "getenv")
  refused({ environment = 3 }, "environment")
  local ok, err = pcall(fixture.load, { options = { unknown = 1 } })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

return T
