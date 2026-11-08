-- Layers in increasing precedence: the schema default, config/default.lua, config/production.lua, an environment
-- variable. The password is a secret: it is wrapped and never printed. The file system and the environment are
-- replaced by tables here; by default `load` reads the real ones.
local config = require("hecate.config")
local schema = require("hecate.schema")

local files = {
  ["config/default.lua"] = "return { database = { host = 'localhost', port = 5433 } }",
  ["config/production.lua"] = "return { database = { host = 'db.internal' } }",
}
local environment = { HECATE_ENV = "production", HECATE_DATABASE__PASSWORD = "s3cr3t" }

local configuration = config.load({
  properties = {
    database = schema.object({
      host = schema.string(),
      port = schema.default(schema.integer({ minimum = 1, maximum = 65535 }), 5432),
      password = schema.string(),
    }),
  },
  secrets = { "database.password" },
  getenv = function(name) return environment[name] end,
  read_file = function(path)
    if files[path] then return files[path] end
    return nil, "no such file", true
  end,
})

print(configuration:get("database.host"), configuration:source("database.host"))
print(configuration:get("database.port"), configuration:source("database.port"))
print(tostring(configuration:get("database.password")), configuration:get("database.password"):reveal() == "s3cr3t")
local database = configuration:get("database")
print(tostring(select(2, pcall(function() database.port = 1 end))):match("immutable"))
-- Prints: db.internal	config/production.lua
-- 5433	config/default.lua
-- [redacted]	true
-- immutable
