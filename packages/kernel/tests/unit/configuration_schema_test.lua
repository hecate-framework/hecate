---@diagnostic disable: need-check-nil, missing-fields, undefined-field
-- `Application:configuration_schema()`: the read-only accessor that tools such as `hecate.doc` use (by duck-typing).
local test = require("harness.test")
local kernel = require("hecate.kernel")
local schema = require("hecate.schema")
local T = test.Case("ConfigurationSchemaTest")

local function loaded(secrets)
  return kernel.load_configuration({
    properties = { greeting = schema.default(schema.string(), "none"), token = schema.optional(schema.string()) },
    secrets = secrets,
    environment = "development",
    read_file = function(path)
      if path == "config/development.lua" then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  })
end

function T:test_returns_the_schema_of_the_configuration_as_one_value()
  local app = kernel.Application({ configuration = loaded({ "token" }), signals = false })
  local json_schema, extra = app:configuration_schema()
  self:assert_equal("object", json_schema.type)
  self:assert_equal("string", json_schema.properties.greeting.type)
  self:assert_not_nil(json_schema.properties.server)
  self:assert_nil(extra, "one value: the secrets are marked inside the schema")
end

function T:test_marks_the_secrets_write_only_and_keeps_their_default()
  local canary = "canary-secret-default-7c2e"
  local configuration = kernel.load_configuration({
    properties = { token = schema.default(schema.string(), canary), greeting = schema.default(schema.string(), "none") },
    secrets = { "token" },
    environment = "development",
    read_file = function(path)
      if path == "config/development.lua" then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  })
  local json_schema = kernel.Application({ configuration = configuration, signals = false }):configuration_schema()
  self:assert_equal(true, json_schema.properties.token.writeOnly)
  self:assert_equal(canary, json_schema.properties.token.default, "the default stays: consumers must honour writeOnly")
  self:assert_nil(json_schema.properties.greeting.writeOnly)
end

function T:test_works_before_boot()
  local app = kernel.Application({ configuration = loaded(), signals = false })
  self:assert_not_nil((app:configuration_schema()))
end

function T:test_without_a_configuration_returns_nil()
  local app = kernel.Application({ signals = false })
  self:assert_nil(app:configuration_schema())
end

return T
