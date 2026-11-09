---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- Environment variable naming and coercion (configuration.md, "Environment variables"); the known pitfall of the package.
local test = require("harness.test")
local config = require("hecate.config")
local schema = require("hecate.schema")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigEnvironmentTest")

function T:test_name_is_prefix_and_path_with_double_underscores()
  self:assert_equal("HECATE_LIMITS__MAX_DEPTH", config.variable_name("HECATE", { "limits", "max_depth" }))
  self:assert_equal("ACME_DATABASE__PORT", config.variable_name("ACME", { "database", "port" }))
end

function T:test_text_is_coerced_by_the_schema_of_the_leaf()
  local configuration = fixture.load({ env = {
    HECATE_DATABASE__PORT = "8080",
    HECATE_DATABASE__TLS = "true",
    HECATE_DATABASE__HOST = "db.internal",
    HECATE_TAGS = "x,y,z",
  } })
  self:assert_equal(8080, configuration:get("database.port"))
  self:assert_equal("integer", math.type(configuration:get("database.port")))
  self:assert_equal(true, configuration:get("database.tls"))
  self:assert_equal("db.internal", configuration:get("database.host"))
  local tags = configuration:get("tags")
  self:assert_equal(3, #tags)
  self:assert_equal("z", tags[3])
end

function T:test_empty_variable_is_set()
  local configuration = fixture.load({ env = { HECATE_DATABASE__HOST = "" } })
  self:assert_equal("", configuration:get("database.host"))
  local err = fixture.failure({ env = { HECATE_DATABASE__PORT = "" } })
  self:assert_equal("coercion", err.context.violations[1].code)
end

function T:test_uncoercible_text_is_a_diagnostic_with_its_variable()
  local err = fixture.failure({ env = { HECATE_DATABASE__PORT = "abc", HECATE_DATABASE__TLS = "yes" } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  local by_path = {}
  for _, violation in ipairs(err.context.violations) do by_path[violation.path] = violation end
  self:assert_equal("coercion", by_path["database.port"].code)
  self:assert_equal("environment variable HECATE_DATABASE__PORT", by_path["database.port"].source)
  self:assert_equal("coercion", by_path["database.tls"].code)
end

function T:test_refinement_of_the_leaf_applies_to_the_text()
  local err = fixture.failure({ env = { HECATE_DATABASE__PORT = "70000" } })
  self:assert_equal("maximum", err.context.violations[1].code)
  self:assert_equal("database.port", err.context.violations[1].path)
  self:assert_equal("environment variable HECATE_DATABASE__PORT", err.context.violations[1].source)
end

function T:test_variables_of_other_names_are_ignored()
  local configuration = fixture.load({ env = { HECATE_DATABSE__PORT = "1", PORT = "2", HECATE_LABELS__A = "x" } })
  self:assert_equal(5432, configuration:get("database.port"))
  self:assert_nil(configuration:get("labels").a, "members of a map are not addressable")
end

function T:test_colliding_names_are_refused()
  local err = fixture.failure({ options = { properties = {
    a_b = schema.optional(schema.string()),
    a = schema.optional(schema.object({ b = schema.optional(schema.string()) })),
    ["a__b"] = schema.optional(schema.string()),
  } } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  self:assert_true(tostring(err):find("HECATE_A__B", 1, true) ~= nil)
end

function T:test_invalid_prefix_is_an_argument_error()
  self:assert_error(function() fixture.load({ options = { env_prefix = "bad-prefix" } }) end, "env_prefix")
  self:assert_error(function() fixture.load({ options = { env_prefix = "" } }) end, "env_prefix")
end

return T
