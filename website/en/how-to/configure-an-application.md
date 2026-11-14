---
description: Configure an application with hecate.config - layers, environment variables, secrets, validation at boot and the logging and depth keys.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Configure an application

The [configuration](../reference/glossary.md#configuration) of a process is the immutable, validated tree of keys that
the process is booted with. `hecate.config` builds it from several sources. Use it to give your application its keys
once, at boot, and to learn at once when one is wrong. This guide is written for hecate 0.x and Lua 5.5.

The specification is [configuration.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/configuration.md).

## Declare the keys and load

Declare the keys of your application as schemas. Then call `config.load`. It reads the sources, merges them,
validates the result against the schemas and returns the configuration. It blocks, so call it at boot, before the
reactor runs.

The example declares a database section. Its host comes from a file, its port from another file and its password from
an environment variable.

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

Read the output line by line.

- `database.host` comes from `config/production.lua`, a later layer than `config/default.lua`.
- `database.port` comes from `config/default.lua`, which wins over the default of the schema (5432).
- The password is a secret object. `tostring` gives `[redacted]`, and `reveal()` gives the value.
- A write to the configuration raises an error that says it is immutable.

### The layers

A [configuration layer](../reference/glossary.md#configuration) is one source of the merge. From the weakest to the
strongest, the layers are:

1. the defaults of the schema;
2. `config/default.lua`;
3. `config/<environment>.lua`;
4. environment variables;
5. secret files.

The [environment](../reference/glossary.md#configuration) names the deployment profile, such as `development`, `test`
or `production`. It selects `config/<environment>.lua`. It is the `environment` option of `config.load`, else the
variable `HECATE_ENV`, else `production`. The prefix `HECATE` is the `env_prefix` option.

### The files

A file under `config/` returns a table. It is evaluated in an empty `_ENV` table, so it has no `require` and no `os`.

Tables merge key by key. An array of a later layer replaces the earlier array as a whole.

## Environment variables

An [environment variable](../reference/glossary.md#configuration) supplies one leaf of the configuration. A leaf is a
declared key that is not an object: a scalar, an enumeration or an array. Its name is derived from the schema:

1. the prefix, `HECATE` by default;
2. an underscore;
3. the path of the leaf in upper case, its segments joined by two underscores.

So `database.port` is `HECATE_DATABASE__PORT`, and `limits.max_depth` is `HECATE_LIMITS__MAX_DEPTH`.

The schema of the key converts the text:

- `"8080"` is an integer;
- `"true"` is a boolean;
- `"a,b"` is an array.

A text that does not convert is reported with the name of its variable. Members of a map are configured by files
only, because the schema does not know the names of its members.

## Secrets

A [secret object](../reference/glossary.md#configuration) wraps the value of a key that must never be printed. List
the keys that hold secrets in the `secrets` option, by their dotted paths:

```lua
local configuration = config.load({
  properties = properties,
  secrets = { "database.password" },
})
```

A path that is not a declared leaf raises `ArgumentError`. The wrapped value shows as `[redacted]` through `tostring`,
and `reveal()` gives the value. `configuration:describe()`, the error messages and the logs never show it.

### Read a secret from a file

A [secret file](../reference/glossary.md#configuration) holds the value of one secret key, as a container platform
mounts it. There are two ways to name it:

- the variable `HECATE_DATABASE__PASSWORD_FILE` holds the path of the file;
- the option `secrets_directory` names a directory that holds a file called `HECATE_DATABASE__PASSWORD`.

A final line end and a byte order mark of the file are removed. A secret file wins over the environment variable. A
file named by `<NAME>_FILE` must exist. A missing file in `secrets_directory` is ignored.

### Wrap the secrets for the logs

The logging sinks must recognise the wrapper. By default, `config.load` uses `hecate.log.Secret` when `hecate.log` is
already loaded, and its own class otherwise. That class prints `[redacted]` through `tostring`, but a sink does not
recognise it. Pass `wrap_secret = log.Secret` to be sure, or call `kernel.load_configuration`, which does it.

## Read and diagnose

`configuration:get("database.port")` returns a typed value. `get` validates the path: a path that the schema does not
declare raises `ArgumentError`. `configuration:values()` gives the root `Section`, which you read by field.

Two methods tell where a value comes from:

- `configuration:source(path)` names the layer that won;
- `configuration:describe()` is the text to log at boot, one line per leaf, with each layer.

### Read an invalid configuration

Unknown keys are errors at every depth. One `ConfigurationError` lists every
[violation](../reference/glossary.md#types-and-validation), each with its dotted path, its code and its layer:

```text
config.load: invalid configuration (2 problems, environment production)
  database.port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)
  databse: the property is not declared [additional_properties] (config/production.lua)
```

`context.violations` also holds the JSON Pointer of each violation. The message of a violation at a secret key never
quotes the value.

## Framework keys

Every configuration declares the framework keys, and an application cannot redeclare them. The logging keys are:

| Key | Meaning | Default |
|---|---|---|
| `logging.severity` | the severity of the default logger | `informational` |
| `logging.severities` | a severity per logger name | none |
| `logging.sinks` | a list of `console`, `json_lines`, `file` | `console` |
| `logging.file.path` | the path of the `file` sink | none |
| `logging.async` | wrap each sink in an asynchronous sink | `false` |
| `logging.redact` | field names to redact, added to the built-in list | none |

The kernel applies the logging keys when it builds the loggers.

`limits.max_depth` is the nesting depth accepted by `hecate.json` and `hecate.schema`. It is an integer from 1 to 1000,
and its default is 1000. A project can lower the depth, never raise it.

`server.grace_timeout` is how long a graceful shutdown lets the requests in flight finish before cancelling them. It
is a number of seconds, 30 by default (`HECATE_SERVER__GRACE_TIMEOUT`). Keep it shorter than the stop timeout of the
deployment: `docker stop` waits 10 seconds by default, and Kubernetes 30 seconds.
