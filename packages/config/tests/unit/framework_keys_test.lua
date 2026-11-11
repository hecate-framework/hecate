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

function T:test_errors_and_requests_keys()
  local configuration = fixture.load({})
  self:assert_equal(false, configuration:get("errors.expose_details"))
  self:assert_equal("strict", configuration:get("requests.inputs"))
  local set = fixture.load({ env = { HECATE_ERRORS__EXPOSE_DETAILS = "true", HECATE_REQUESTS__INPUTS = "lax" } })
  self:assert_equal(true, set:get("errors.expose_details"))
  self:assert_equal("lax", set:get("requests.inputs"))
  local err = fixture.failure({ env = { HECATE_REQUESTS__INPUTS = "loose" } })
  self:assert_equal("requests.inputs", err.context.violations[1].path)
end

function T:test_grace_timeout_default_and_text_coercion()
  self:assert_equal(30, fixture.load({}):get("server.grace_timeout"))
  self:assert_equal(2.5, fixture.load({ env = { HECATE_SERVER__GRACE_TIMEOUT = "2.5" } }):get("server.grace_timeout"))
  self:assert_equal(0, fixture.load({ env = { HECATE_SERVER__GRACE_TIMEOUT = "0" } }):get("server.grace_timeout"))
  self:assert_equal("HECATE_SERVER__GRACE_TIMEOUT", config.variable_name("HECATE", { "server", "grace_timeout" }))
  local from_file = fixture.load({ files = { ["config/default.lua"] = "return { server = { grace_timeout = 5 } }" } })
  self:assert_equal(5, from_file:get("server.grace_timeout"))
end

function T:test_grace_timeout_must_be_a_non_negative_finite_number()
  for _, text in ipairs({ "-1", "-0.5", "nan", "inf", "-inf", "abc", "" }) do
    local err = fixture.failure({ env = { HECATE_SERVER__GRACE_TIMEOUT = text } })
    self:assert_equal("server.grace_timeout", err.context.violations[1].path, text)
  end
  for _, literal in ipairs({ "0/0", "1e999", "-1e999", "-1", "'5'", "true" }) do
    local err = fixture.failure({ files = { ["config/default.lua"] =
      "return { server = { grace_timeout = " .. literal .. " } }" } })
    self:assert_equal("server.grace_timeout", err.context.violations[1].path, literal)
  end
end

function T:test_workers_and_strategy_defaults_and_text_coercion()
  local defaults = fixture.load({})
  self:assert_equal(1, defaults:get("server.workers"))
  self:assert_equal("auto", defaults:get("server.strategy"))
  local set = fixture.load({ env = { HECATE_SERVER__WORKERS = "4", HECATE_SERVER__STRATEGY = "round_robin" } })
  self:assert_equal(4, set:get("server.workers"))
  self:assert_equal("round_robin", set:get("server.strategy"))
  self:assert_equal("HECATE_SERVER__WORKERS", config.variable_name("HECATE", { "server", "workers" }))
  self:assert_equal("HECATE_SERVER__STRATEGY", config.variable_name("HECATE", { "server", "strategy" }))
  local from_file = fixture.load({ files = { ["config/default.lua"] =
    "return { server = { workers = 3, strategy = 'reuseport' } }" } })
  self:assert_equal(3, from_file:get("server.workers"))
  self:assert_equal("reuseport", from_file:get("server.strategy"))
end

function T:test_workers_and_strategy_are_validated()
  for _, text in ipairs({ "0", "-1", "1.5", "abc", "" }) do
    local err = fixture.failure({ env = { HECATE_SERVER__WORKERS = text } })
    self:assert_equal("server.workers", err.context.violations[1].path, text)
  end
  local err = fixture.failure({ env = { HECATE_SERVER__STRATEGY = "fork" } })
  self:assert_equal("server.strategy", err.context.violations[1].path)
end

return T
