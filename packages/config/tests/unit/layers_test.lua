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
  local source = { database = { port = 1 } }
  local calls = 0
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { database = { port = 6000 } }" },
    options = { read_file = function(path)
      calls = calls + 1
      if path == "config/default.lua" then return "return { database = { port = 6000 } }" end
      return nil, "absent", true
    end },
  })
  self:assert_equal(6000, configuration:get("database.port"))
  self:assert_equal(1, source.database.port)
  self:assert_true(calls >= 1)
end

return T
