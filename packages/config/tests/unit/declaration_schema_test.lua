---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- `Configuration:schema()` and `Configuration:secrets()`: the declaration of the configuration, readable for tools
-- (the configuration reference of `hecate.doc`). Read-only: a caller cannot change the configuration through them.
local test = require("harness.test")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigDeclarationSchemaTest")

function T:test_schema_is_the_json_schema_of_every_declared_key()
  local schema = fixture.load({}):schema()
  self:assert_equal("object", schema.type)
  self:assert_equal("integer", schema.properties.database.properties.port.type)
  self:assert_equal(5432, schema.properties.database.properties.port.default)
  self:assert_not_nil(schema.properties.logging, "the framework keys are declared too")
  self:assert_not_nil(schema.properties.server.properties.workers)
end

function T:test_schema_is_a_fresh_table_each_call()
  local configuration = fixture.load({})
  local first = configuration:schema()
  first.properties.name = nil
  self:assert_not_nil(configuration:schema().properties.name)
end

function T:test_secrets_are_the_declared_paths_sorted()
  local configuration = fixture.load({ options = { secrets = { "name", "database.password" } } })
  self:assert_equal("database.password,name", table.concat(configuration:secrets(), ","))
end

function T:test_secrets_is_a_fresh_list_and_empty_by_default()
  local configuration = fixture.load({ options = { secrets = { "database.password" } } })
  configuration:secrets()[1] = "changed"
  self:assert_equal("database.password", table.concat(configuration:secrets(), ","))
  self:assert_equal(0, #fixture.load({}):secrets())
end

return T
