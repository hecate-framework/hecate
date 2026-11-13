---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- Layer precedence (configuration.md, "Layers and precedence"): schema defaults < default.lua < <environment>.lua <
-- environment variables < secret files.
local test = require("harness.test")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigLayersTest")

function T:test_schema_defaults_alone()
  local configuration = fixture.load({})
  self:assert_equal("localhost", configuration:get("database.host"))
  self:assert_equal(5432, configuration:get("database.port"))
  self:assert_equal("production", configuration:environment())
  self:assert_equal("schema default", configuration:source("database.port"))
end

function T:test_default_file_wins_over_schema_defaults()
  local configuration = fixture.load({ files = { ["config/default.lua"] = "return { database = { port = 6000 } }" } })
  self:assert_equal(6000, configuration:get("database.port"))
  self:assert_equal("localhost", configuration:get("database.host"))
  self:assert_equal("config/default.lua", configuration:source("database.port"))
end

function T:test_environment_file_wins_over_default_file()
  local configuration = fixture.load({
    files = {
      ["config/default.lua"] = "return { database = { port = 6000, host = 'db' } }",
      ["config/production.lua"] = "return { database = { port = 7000 } }",
    },
    options = { environment = "production" },
  })
  self:assert_equal(7000, configuration:get("database.port"))
  self:assert_equal("db", configuration:get("database.host"), "keys of the earlier layer are kept")
  self:assert_equal("config/production.lua", configuration:source("database.port"))
  self:assert_equal("config/default.lua", configuration:source("database.host"))
  self:assert_equal("production", configuration:environment())
end

function T:test_environment_variable_wins_over_files()
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { database = { port = 6000 } }" },
    env = { HECATE_DATABASE__PORT = "8080" },
  })
  self:assert_equal(8080, configuration:get("database.port"))
  self:assert_equal("environment variable HECATE_DATABASE__PORT", configuration:source("database.port"))
end

function T:test_secret_file_wins_over_environment_variable()
  local configuration = fixture.load({
    env = { HECATE_DATABASE__PASSWORD = "from-env" },
    files = { ["/run/secrets/HECATE_DATABASE__PASSWORD"] = "from-file\n" },
    options = { secrets = { "database.password" }, secrets_directory = "/run/secrets" },
  })
  self:assert_equal("from-file", configuration:get("database.password"):reveal())
  self:assert_equal("secret file /run/secrets/HECATE_DATABASE__PASSWORD", configuration:source("database.password"))
end

-- A section that only a later layer created names that layer, not `schema default` (review finding CF-6).
function T:test_source_of_a_section_created_by_environment_variables_names_that_layer()
  local schema = require("hecate.schema")
  local configuration = fixture.load({ env = { HECATE_DATABASE__PORT = "8080", HECATE_DATABASE__HOST = "db" } })
  -- the first leaf in path order that created the section
  self:assert_equal("environment variable HECATE_DATABASE__HOST", configuration:source("database"))
  local nested = fixture.load({
    env = { HECATE_OUTER__INNER__COUNT = "3" },
    options = { properties = { outer = schema.default(schema.object({
      inner = schema.default(schema.object({ count = schema.optional(schema.integer()) }), {}) }), {}) } },
  })
  self:assert_equal("environment variable HECATE_OUTER__INNER__COUNT", nested:source("outer"))
  self:assert_equal("environment variable HECATE_OUTER__INNER__COUNT", nested:source("outer.inner"))
  self:assert_equal("schema default", fixture.load({}):source("database"))
end

function T:test_source_of_a_section_created_by_a_secret_file_names_that_layer()
  local configuration = fixture.load({
    env = { HECATE_DATABASE__PASSWORD_FILE = "/run/secrets/password" },
    files = { ["/run/secrets/password"] = "value" },
    options = { secrets = { "database.password" } },
  })
  self:assert_equal("secret file /run/secrets/password", configuration:source("database"))
end

function T:test_source_of_a_section_from_a_file_is_kept_when_a_variable_adds_a_key()
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { database = { host = 'db' } }" },
    env = { HECATE_DATABASE__PORT = "8080" },
  })
  self:assert_equal("config/default.lua", configuration:source("database"))
end

function T:test_arrays_are_replaced_and_maps_are_merged()
  local configuration = fixture.load({
    files = {
      ["config/default.lua"] = "return { tags = { 'x', 'y' }, labels = { a = '1', b = '2' } }",
      ["config/test.lua"] = "return { tags = { 'z' }, labels = { b = '3', c = '4' } }",
    },
    options = { environment = "test" },
  })
  self:assert_equal(1, #configuration:get("tags"))
  self:assert_equal("z", configuration:get("tags")[1])
  local labels = configuration:get("labels")
  self:assert_equal("1", labels.a)
  self:assert_equal("3", labels.b)
  self:assert_equal("4", labels.c)
end

function T:test_environment_comes_from_the_variable()
  local configuration = fixture.load({
    env = { HECATE_ENV = "development" },
    files = { ["config/development.lua"] = "return { name = 'dev' }" },
  })
  self:assert_equal("development", configuration:environment())
  self:assert_equal("dev", configuration:get("name"))
end

-- The specification refuses an empty `HECATE_ENV` (it does not match the pattern); it is not read as unset (review
-- finding CF-7). Not run on Windows, where an empty variable is the same as an unset one (OQ-110 (6)).
function T:test_an_empty_environment_variable_is_refused()
  if package.config:sub(1, 1) == "\\" then return end
  local err = fixture.failure({ env = { HECATE_ENV = "" } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  self:assert_true(tostring(err):find("HECATE_ENV", 1, true) ~= nil, tostring(err))
end

function T:test_environment_defaults_to_production_without_option_or_variable()
  local configuration = fixture.load({ files = { ["config/production.lua"] = "return { name = 'prod' }" } })
  self:assert_equal("production", configuration:environment())
  self:assert_equal("prod", configuration:get("name"))
end

function T:test_option_development_wins_over_the_default()
  local configuration = fixture.load({
    files = { ["config/development.lua"] = "return { name = 'dev' }" },
    options = { environment = "development" },
  })
  self:assert_equal("development", configuration:environment())
  self:assert_equal("dev", configuration:get("name"))
end

function T:test_option_wins_over_the_environment_variable_for_the_environment()
  local configuration = fixture.load({
    env = { HECATE_ENV = "production" },
    files = { ["config/test.lua"] = "return { name = 'testing' }" },
    options = { environment = "test" },
  })
  self:assert_equal("testing", configuration:get("name"))
end

function T:test_missing_default_file_is_empty_and_implicit_environment_file_may_be_absent()
  self:assert_equal("app", fixture.load({}):get("name"))
end

function T:test_explicit_environment_without_file_is_an_error()
  local err = fixture.failure({ env = { HECATE_ENV = "prodution" } })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  self:assert_true(tostring(err):find("config/prodution.lua", 1, true) ~= nil)
  local err2 = fixture.failure({ options = { environment = "staging" } })
  self:assert_true(tostring(err2):find("config/staging.lua", 1, true) ~= nil)
end

function T:test_environment_name_cannot_escape_the_directory()
  self:assert_error(function() fixture.load({ options = { environment = "../etc" } }) end, "environment")
end

function T:test_directory_and_prefix_options()
  local configuration = fixture.load({
    files = { ["conf/default.lua"] = "return { name = 'x' }", ["conf/production.lua"] = "return { tags = { 'p' } }" },
    env = { ACME_DATABASE__PORT = "9", ACME_ENV = "production", HECATE_DATABASE__PORT = "1" },
    options = { directory = "conf", env_prefix = "ACME" },
  })
  self:assert_equal("x", configuration:get("name"))
  self:assert_equal(9, configuration:get("database.port"))
  self:assert_equal("p", configuration:get("tags")[1])
end

function T:test_layers_are_not_modified()
  -- The table a file returns is the caller's own data: `read_file` hands out the text, and the loaded configuration must
  -- not alias anything a later load can see. Two loads of the same text give independent, equal results.
  local text = "return { database = { port = 6000 }, tags = { 'x' } }"
  local first = fixture.load({ files = { ["config/default.lua"] = text } })
  local second = fixture.load({ files = { ["config/default.lua"] = text } })
  self:assert_equal(6000, first:get("database.port"))
  self:assert_false(rawequal(first:get("tags"), second:get("tags")))
  self:assert_false(rawequal(first:get("database"), second:get("database")))
  self:assert_equal(6000, second:get("database.port"))
end

function T:test_environment_variable_false_overrides_a_file_true()
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { database = { tls = true } }" },
    env = { HECATE_DATABASE__TLS = "false" },
  })
  self:assert_equal(false, configuration:get("database.tls"))
  self:assert_equal("environment variable HECATE_DATABASE__TLS", configuration:source("database.tls"))
end

function T:test_secret_file_false_overrides_a_file_true()
  local schema = require("hecate.schema")
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { flag = true }", ["/run/secrets/HECATE_FLAG"] = "false\n" },
    options = {
      properties = { flag = schema.default(schema.boolean(), true) },
      secrets = { "flag" }, secrets_directory = "/run/secrets",
      wrap_secret = function(value) return { wrapped = value } end,
    },
  })
  self:assert_equal(false, configuration:get("flag").wrapped)
  self:assert_equal("secret file /run/secrets/HECATE_FLAG", configuration:source("flag"))
end

-- Documented in website/en/how-to/before-going-to-production.md (Secrets).
function T:test_secret_file_named_by_the_file_variable_wins_over_environment_variable()
  local configuration = fixture.load({
    env = { HECATE_DATABASE__PASSWORD = "from-env", HECATE_DATABASE__PASSWORD_FILE = "/mnt/password" },
    files = { ["/mnt/password"] = "from-file\n" },
    options = { secrets = { "database.password" } },
  })
  self:assert_equal("from-file", configuration:get("database.password"):reveal())
  self:assert_equal("secret file /mnt/password", configuration:source("database.password"))
end

return T
