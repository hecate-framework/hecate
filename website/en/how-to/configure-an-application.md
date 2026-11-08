---
description: Configure an application with hecate.config - layers, environment variables, secrets, validation at boot and the logging and depth keys.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Configure an application

This guide shows how to load the configuration of a process with `hecate.config`. It is written for
hecate 0.x and Lua 5.5. The configuration is read once at boot, validated against a schema and then
immutable; the specification is [configuration.md](../../../docs/architecture/configuration.md).

## Declare the keys and load

Declare the keys of your application as schemas, then call `config.load`. The layers, from the weakest
to the strongest, are the defaults of the schema, `config/default.lua`, `config/<environment>.lua`,
environment variables and secret files. The environment is `HECATE_ENV` (default `production`).

<!-- example: packages/config/examples/hecate.config.load.lua -->
```lua
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
```

A file under `config/` returns a table and is evaluated in an empty environment (no `require`, no
`os`). Tables merge key by key; an array of a later layer replaces the earlier one.

## Environment variables

The name of a variable is derived from the schema: the prefix (`HECATE`, option `env_prefix`), then the
upper-case path joined by two underscores, for example `HECATE_DATABASE__PORT` or
`HECATE_LIMITS__MAX_DEPTH`. The text is converted by the schema of the key: `"8080"` is an integer,
`"true"` a boolean, `"a,b"` an array. A text that does not convert is reported with the name of its variable.
Members of a map are configured by files only.

## Secrets

List the keys that hold secrets in the `secrets` option. Their values are wrapped (`tostring` gives
`[redacted]`, `reveal()` gives the value) and `configuration:describe()`, the error messages and the
logs never show them. A secret can be read from a file: `HECATE_DATABASE__PASSWORD_FILE` names it, or
set `secrets_directory` to the directory where your platform mounts secrets. Pass `secret = log.Secret`
so that the logging sinks recognise the wrapper.

## Read and diagnose

`configuration:get("database.port")` returns a typed value; a path the schema does not declare raises
`ArgumentError`. `configuration:source(path)` tells which layer won, and `configuration:describe()` is
the text to log at boot. Unknown keys are errors at every depth, and one `ConfigurationError` lists
every problem with its JSON Pointer, its code and its layer:

```text
config.load: invalid configuration (2 problems, environment production)
  /database/port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)
  /databse: the property is not declared [additional_properties] (config/production.lua)
```

## Logging and depth keys

Every configuration has `logging.severity` (default `informational`), `logging.severities` (a severity per
logger name), `logging.sinks` (`console`, `json_lines`, `file`), `logging.file.path`, `logging.async` and
`logging.redact`, which the kernel applies when it builds the loggers, and `limits.max_depth` (1 to 1000),
the nesting depth of `hecate.json` and `hecate.schema`. A project can lower the depth, never raise it.
