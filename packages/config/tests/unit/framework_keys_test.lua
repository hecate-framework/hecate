---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- The framework keys: logging (OQ-62) and limits.max_depth (OQ-92), configuration.md.
local test = require("harness.test")
local config = require("hecate.config")
local json = require("hecate.json")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigFrameworkKeysTest")

function T:test_logging_defaults()
  local configuration = fixture.load({})
  self:assert_equal("informational", configuration:get("logging.severity"))
  self:assert_equal(1, #configuration:get("logging.sinks"))
  self:assert_equal("console", configuration:get("logging.sinks")[1])
  self:assert_equal(false, configuration:get("logging.async"))
  self:assert_equal(0, #configuration:get("logging.redact"))
  self:assert_nil(configuration:get("logging.file"))
  self:assert_nil(next(configuration:get("logging.severities")))
end

function T:test_logging_from_a_file_with_named_severities()
  local configuration = fixture.load({ files = { ["config/default.lua"] = [[
    return { logging = {
      severity = "warning",
      severities = { ["hecate.http"] = "debug", app = "error" },
      sinks = { "json_lines", "file" },
      file = { path = "app.log" },
      async = true,
      redact = { "password" },
    } }]] } })
  self:assert_equal("warning", configuration:get("logging.severity"))
  self:assert_equal("debug", configuration:get("logging.severities")["hecate.http"])
  self:assert_equal("error", configuration:get("logging.severities").app)
  self:assert_equal("app.log", configuration:get("logging.file.path"))
  self:assert_equal(true, configuration:get("logging.async"))
  self:assert_equal("password", configuration:get("logging.redact")[1])
end

function T:test_logging_from_environment_variables()
  local configuration = fixture.load({ env = {
    HECATE_LOGGING__SEVERITY = "debug",
    HECATE_LOGGING__SINKS = "console,file",
    HECATE_LOGGING__FILE__PATH = "x.log",
    HECATE_LOGGING__ASYNC = "true",
    HECATE_LOGGING__REDACT = "token,password",
  } })
  self:assert_equal("debug", configuration:get("logging.severity"))
  self:assert_equal("file", configuration:get("logging.sinks")[2])
  self:assert_equal("x.log", configuration:get("logging.file.path"))
  self:assert_equal(true, configuration:get("logging.async"))
  self:assert_equal(2, #configuration:get("logging.redact"))
end

function T:test_severity_names_are_the_eight_of_rfc_5424_and_info_does_not_exist()
  for _, name in ipairs({ "emergency", "alert", "critical", "error", "warning", "notice", "informational", "debug" }) do
    self:assert_equal(name, fixture.load({ env = { HECATE_LOGGING__SEVERITY = name } }):get("logging.severity"))
  end
  for _, name in ipairs({ "info", "warn", "trace", "" }) do
    local err = fixture.failure({ env = { HECATE_LOGGING__SEVERITY = name } })
    self:assert_equal("logging.severity", err.context.violations[1].path, name)
  end
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { logging = { severities = { app = 'info' } } }" } })
  self:assert_equal("logging.severities.app", err.context.violations[1].path)
end

function T:test_unknown_sink_is_refused()
  local err = fixture.failure({ env = { HECATE_LOGGING__SINKS = "console,syslog" } })
  self:assert_equal("logging.sinks.1", err.context.violations[1].path)
end

function T:test_severity_names_equal_log_severity_when_log_is_loadable()
  -- `hecate.log.severity` needs only `core`; the full `hecate.log` needs libuv.
  local ok, Severity = pcall(require, "hecate.log.severity")
  self:assert_true(ok, "hecate.log.severity must be loadable")
  self:assert_equal(Severity:size(), #config.SEVERITIES)
  for index, name in ipairs(Severity:names()) do self:assert_equal(name, config.SEVERITIES[index]) end
end

function T:test_max_depth_default_and_ceiling_follow_json()
  local configuration = fixture.load({})
  self:assert_equal(json.DEFAULT_MAX_DEPTH, configuration:get("limits.max_depth"))
  self:assert_equal(json.MAX_DEPTH_CEILING, config.MAX_DEPTH_CEILING)
end

function T:test_max_depth_can_be_lowered_never_raised()
  self:assert_equal(64, fixture.load({ env = { HECATE_LIMITS__MAX_DEPTH = "64" } }):get("limits.max_depth"))
  self:assert_equal(1, fixture.load({ env = { HECATE_LIMITS__MAX_DEPTH = "1" } }):get("limits.max_depth"))
  for _, text in ipairs({ "1001", "0", "-5", "abc", "1.5" }) do
    local err = fixture.failure({ env = { HECATE_LIMITS__MAX_DEPTH = text } })
    self:assert_equal("limits.max_depth", err.context.violations[1].path, text)
  end
  local err = fixture.failure({ files = { ["config/default.lua"] = "return { limits = { max_depth = 2000 } }" } })
  self:assert_equal("maximum", err.context.violations[1].code)
end

return T
