---
description: Configure an application with hecate.config - layers, environment variables, secrets, validation at boot and the framework keys for logging, depth and shutdown.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Configure an application

This guide shows how to load the configuration of a process with `hecate.config`. It is written for hecate 0.x and
Lua 5.5.

The [configuration](../reference/glossary.md#configuration) is the immutable, validated key-value tree a process is
booted with. It is read once at boot, validated against a schema, then frozen. The specification is
[configuration.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/configuration.md).

## Declare the keys and load

Declare the keys of your application as schemas, then call `config.load`. Here is a database section read from two
files and an environment variable:

<!-- example: packages/config/examples/hecate.config.load.lua -->
```lua
-- Layers in increasing precedence: the schema default, config/default.lua,
-- config/production.lua, an environment variable. The password is a secret:
-- it is wrapped and never printed. The file system and the environment are
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
-- Prints: db.internal	config/production.lua
print(configuration:get("database.port"), configuration:source("database.port"))
-- Prints: 5433	config/default.lua
print(tostring(configuration:get("database.password")), configuration:get("database.password"):reveal() == "s3cr3t")
-- Prints: [redacted]	true
local database = configuration:get("database")
print(tostring(select(2, pcall(function() database.port = 1 end))):match("immutable"))
-- Prints: immutable
```

The configuration is merged from [configuration layers](../reference/glossary.md#configuration), the sources of the
merge. From the weakest to the strongest:

1. the defaults of the schema;
2. `config/default.lua`;
3. `config/<environment>.lua`;
4. environment variables;
5. secret files.

The [environment](../reference/glossary.md#configuration) is the name of the deployment profile, such as
`development`, `test` or `production`. It selects the file of layer 3. It is read from `HECATE_ENV`, and defaults to
`production`.

## Write a configuration file

A file under `config/` returns a table. It is evaluated in an empty `_ENV` table, so it has no `require` and no `os`.

The layers merge tables key by key. An array is not merged: the array of a later layer replaces the earlier one.

## Set a key from an environment variable

The name of an [environment variable](../reference/glossary.md#configuration) is derived from the path of its key:
the prefix (`HECATE`, option `env_prefix`), then the upper-case path joined by two underscores.
`config.variable_name` computes it:

```lua
local config = require("hecate.config")

print(config.variable_name("HECATE", { "database", "port" }))
-- Prints: HECATE_DATABASE__PORT
print(config.variable_name("HECATE", { "limits", "max_depth" }))
-- Prints: HECATE_LIMITS__MAX_DEPTH
```

The text of the variable is converted by the schema of the key:

- `"8080"` is an integer;
- `"true"` is a boolean;
- `"a,b"` is an array.

A text that does not convert is reported with the name of its variable.

Members of a map are configured by files only.

## Keep secrets out of the output

List the keys that hold secrets in the `secrets` option. Their values are wrapped in a
[secret object](../reference/glossary.md#configuration):

- `tostring` gives `[redacted]`;
- `reveal()` gives the value.

`configuration:describe()`, the error messages and the logs never show them.

A secret can come from a [secret file](../reference/glossary.md#configuration), a file that holds the value of one
secret key. There are two ways to name it:

- the variable `HECATE_DATABASE__PASSWORD_FILE` names the file of the key `database.password`;
- the `secrets_directory` option names the directory where your platform mounts secrets.

Pass `wrap_secret = log.Secret` so that the logging sinks recognise the wrapper.

## Read and diagnose

`configuration:get("database.port")` returns a typed value. `get` validates the path: a path the schema does not
declare raises `ArgumentError`. `configuration:values()` gives the root section, to read by field.

Two methods help at boot:

- `configuration:source(path)` tells which layer won;
- `configuration:describe()` is the text to log at boot.

Unknown keys are errors at every depth. One `ConfigurationError` lists every
[violation](../reference/glossary.md#types-and-validation), one reason a value does not conform to its schema. Each
line gives the dotted path, the code and the layer:

```text
config.load: invalid configuration (2 problems, environment production)
  database.port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)
  databse: the property is not declared [additional_properties] (config/production.lua)
```

`context.violations` also holds the JSON Pointer of each violation.

## Use the framework keys

Every configuration has the keys below. The kernel applies the `logging.*` keys when it builds the loggers.

| Key | Default | Meaning |
|---|---|---|
| `logging.severity` | `informational` | the severity of the loggers |
| `logging.severities` | none | a severity per logger name |
| `logging.sinks` | `console` | among `console`, `json_lines` and `file` |
| `logging.file.path` | none | the file of the `file` sink |
| `logging.async` | `false` | wrap each sink in an `AsyncSink` |
| `logging.redact` | none | field names to redact |
| `limits.max_depth` | 1000 | nesting depth of `hecate.json` and `hecate.schema`, from 1 to 1000 |
| `server.grace_timeout` | 30 | seconds of a graceful shutdown |

A project can lower `limits.max_depth`, never raise it.

`server.grace_timeout` (`HECATE_SERVER__GRACE_TIMEOUT`) is how long a graceful shutdown lets the requests in flight
finish before cancelling them. Keep it shorter than the stop timeout of the deployment: `docker stop` waits 10 s by
default, Kubernetes 30 s.

Every key and its default is in [Configuration keys](../reference/configuration-keys.md).
