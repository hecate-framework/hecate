-- Test support: an in-memory file system and environment for `config.load` (configuration.md, "Testing guidance").
local config = require("hecate.config")
local schema = require("hecate.schema")

local fixture = {}

--- The application properties used by most tests.
---@return table<string, hecate.schema.Schema>
function fixture.properties()
  return {
    name = schema.default(schema.string(), "app"),
    database = schema.default(schema.object({
      host = schema.default(schema.string(), "localhost"),
      port = schema.default(schema.integer({ minimum = 1, maximum = 65535 }), 5432),
      password = schema.optional(schema.string()),
      tls = schema.default(schema.boolean(), false),
    }), {}),
    tags = schema.default(schema.array(schema.string()), { "a" }),
    labels = schema.default(schema.map(schema.string()), {}),
  }
end

--- Loads with an in-memory world. `files` maps a path to its content, `env` maps a variable to its value.
---@param world { files?: table<string, string>, env?: table<string, string>, options?: table }
---@return hecate.config.Configuration
function fixture.load(world)
  local files, env = world.files or {}, world.env or {}
  local options = {
    properties = fixture.properties(),
    getenv = function(name) return env[name] end,
    read_file = function(path)
      local text = files[path]
      if text == nil then return nil, "no such file: " .. path, true end
      return text
    end,
  }
  for key, value in pairs(world.options or {}) do options[key] = value end
  return config.load(options)
end

--- The violations of the `ConfigurationError` that loading raises.
---@param world table
---@return any error  a `hecate.core.ConfigurationError`
function fixture.failure(world)
  local ok, err = pcall(fixture.load, world)
  assert(not ok, "expected the load to fail")
  return err
end

return fixture
