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

-- Secrets are marked `writeOnly` in the schema (JSON Schema 2020-12, 9.4): the default stays, the consumer redacts it.
local CANARY = "canary-secret-default-1f3a"

local function marked(configuration, path)
  local node = configuration:schema()
  for segment in path:gmatch("[^.]+") do node = node.properties[segment] end
  return node.writeOnly
end

function T:test_schema_marks_the_secret_keys_write_only_and_keeps_their_default()
  local configuration = fixture.load({ options = {
    secrets = { "database.password", "name" },
    properties = (function()
      local properties = fixture.properties()
      properties.name = require("hecate.schema").default(require("hecate.schema").string(), CANARY)
      return properties
    end)(),
  } })
  local schema = configuration:schema()
  self:assert_equal(true, schema.properties.name.writeOnly)
  self:assert_equal(CANARY, schema.properties.name.default, "the default stays: consumers must honour writeOnly")
  self:assert_equal(true, marked(configuration, "database.password"))
  self:assert_nil(marked(configuration, "database.host"), "a key that is not a secret is not marked")
  self:assert_nil(marked(configuration, "database.port"))
  self:assert_nil(schema.properties.database.writeOnly, "the container is not marked")
end

function T:test_schema_marks_nothing_without_secrets()
  self:assert_nil(marked(fixture.load({}), "name"))
end

function T:test_schema_marks_a_secret_list_as_a_whole()
  local configuration = fixture.load({ options = { secrets = { "tags" } } })
  self:assert_equal(true, marked(configuration, "tags"))
  self:assert_nil(marked(configuration, "labels"), "a map is not a leaf: it cannot be declared secret")
  self:assert_nil(configuration:schema().properties.tags.items.writeOnly, "the items inherit it from the list")
end

function T:test_schema_marks_a_secret_below_an_optional_nullable_or_named_object()
  local schema = require("hecate.schema")
  local configuration = fixture.load({ options = {
    properties = {
      a = schema.optional(schema.object({ token = schema.optional(schema.string()) })),
      b = schema.default(schema.nullable(schema.object({ token = schema.optional(schema.string()) })), {}),
      c = schema.optional(schema.named("Creds", schema.object({ token = schema.optional(schema.string()) }))),
    },
    secrets = { "a.token", "b.token", "c.token" },
  } })
  local emitted = configuration:schema()
  self:assert_equal(true, emitted.properties.a.properties.token.writeOnly)
  local nullable_object
  for _, alternative in ipairs(emitted.properties.b.anyOf) do
    if alternative.properties then nullable_object = alternative end
  end
  self:assert_equal(true, nullable_object.properties.token.writeOnly)
  self:assert_equal(true, emitted["$defs"].Creds.properties.token.writeOnly)
end

function T:test_schema_marking_changes_neither_the_declaration_nor_the_values()
  local configuration = fixture.load({ options = { secrets = { "database.password" } },
    env = nil, files = nil })
  local first = configuration:schema()
  first.properties.database.properties.password.writeOnly = nil
  self:assert_equal(true, marked(configuration, "database.password"), "a fresh table at each call")
  self:assert_equal("database.password", table.concat(configuration:secrets(), ","))
  self:assert_equal(5432, configuration:get("database.port"))
  self:assert_nil(configuration:get("database.password"))
end

return T
