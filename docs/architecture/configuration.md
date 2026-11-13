# Configuration (`hecate.config`)

Package: `config` (layer 3, Framework). Status: implemented in Phase 2 (alpha). Decisions: none specific; the choices
that no ADR settles were taken conservatively and confirmed by the owner, see [OQ-101](../open-questions.md). Standard: The Twelve-Factor
App, factor III ("Config"): configuration that varies between deploys is kept apart from the code and read from the
environment. Vocabulary: [glossary](../glossary.md), section "Configuration".

## Scope and non-goals

`hecate.config` builds the **configuration** of a process at boot: it reads the layers below, merges them, validates the result
against a schema (`hecate.schema`) and returns an immutable `Configuration`. It is step 1 of the boot sequence
([overview.md](overview.md)): an invalid configuration aborts the boot with a precise diagnostic, and nothing is validated lazily.

Its dependencies are `core` and `schema`. It does not depend on `log`, `json` or `reactor`: the logging keys are *declared* here and
*applied* by the kernel (see "Logging keys").

Non-goals: remote configuration services (later, by a separate package); reloading a configuration in a running process (the configuration is
immutable after boot, a change means a restart); writing configuration files; interpolation of one key in another; any
configuration language other than Lua tables.

## Layers and precedence

A configuration is the merge of up to five layers. **A later layer wins over an earlier one**:

| # | Layer | Source | Name in diagnostics |
|---|---|---|---|
| 1 | schema defaults | `schema.default(inner, value)` in the declared schema | `schema default` |
| 2 | default file | `config/default.lua` | `config/default.lua` |
| 3 | environment file | `config/<environment>.lua` | `config/production.lua` |
| 4 | environment variables | derived names, see "Environment variables" | `environment variable HECATE_DATABASE__PORT` |
| 5 | secret files | see "Secret files" | `secret file /run/secrets/...` |

Factor III asks for the deploy-specific values to come from the environment: layers 4 and 5 are those; layers 2 and 3 hold what
is reviewed with the code (the environment file is the committed layer of one *environment*, such as `production`, and not a place for secrets).

### Files

- `config/default.lua` and `config/<environment>.lua` each return one table. The directory is the `directory` option, default
  `config`, relative to the working directory.
- A file is evaluated with `load` in text mode in an **empty `_ENV` table**, as the project manifest is
  ([ADR 0009](../adr/0009-project-manifest.md)): no `require`, no `os`, no `io`, no globals. It is trusted code (it is part of
  the project), so a file that loops forever blocks the boot; the sandbox protects against accidents, not against hostile files.
- `default.lua` may be absent (it counts as an empty table). `<environment>.lua` may be absent only when the environment was not
  chosen explicitly (below); a missing file for an explicit environment is an error, so that a typo in the name never falls back
  silently.
- A leading UTF-8 byte order mark is ignored (in configuration files and secret files). The message of a syntax error keeps the
  file name and the line but not the text near it, which may be a secret. A directory in place of a file is a read error.
- A file that cannot be read, has a syntax error, raises, or does not return a table raises `hecate.core.ConfigurationError` at
  once, naming the file. A file is not partially applied.

### The environment

The *environment* is the name of the deployment: `development`, `test`, `production` or any name that matches
`^[a-z][a-z0-9_]*$` (the pattern keeps a name from escaping the directory). It is the `environment` option, else the environment
variable `<PREFIX>_ENV` (for the default prefix, `HECATE_ENV`), else `production` (the safer environment: a process that is not told otherwise never runs with
development configuration). The last case is the only implicit one, so an absent `config/production.lua` does not stop the boot.
`Configuration:environment()` returns it.

### Merging

Layers are merged key by key, into a fresh table, never modifying a layer:

- two tables (an `object` or a `map`) merge recursively: keys of the later layer win, other keys are kept;
- anything else, **arrays included**, is replaced by the later value as a whole (concatenating lists across layers is a source of
  surprises that nobody can read back from one file);
- a layer cannot remove a key (there is no `nil` in a table); to turn a feature off, declare a key that says so.

The origin of every key is tracked: `Configuration:source(path)` and the diagnostics name the layer that supplied the final value.

## Environment variables

The process environment cannot be enumerated from Lua, so the variables that are read are **derived from the schema**: for each
leaf of the declared schema, the name is

```text
<PREFIX>_<SEGMENT>__<SEGMENT>...        PREFIX default HECATE; segments upper-cased, joined by two underscores
```

for example `limits.max_depth` is `HECATE_LIMITS__MAX_DEPTH`, `database.port` is `HECATE_DATABASE__PORT`. The double underscore is
what keeps `max_depth` apart from a nested `max` / `depth` pair, and two leaves whose names collide are a `ConfigurationError` at
load. So is a leaf whose name is reserved: `<PREFIX>_ENV` (the environment) and, for each secret key, `<NAME>_FILE` (its secret file). The prefix is the `env_prefix` option (upper case letters, digits and underscores, starting with a letter).

- A *leaf* is a declared property that is not an `object`: scalars, enumerations, and arrays. Properties inside a `map` and the
  members of an array are not addressable (their names are not known to the schema); a map or an object array is configured by
  files only.
- The text is converted by the **coercion** of the leaf's schema (`Schema:coerce`): `"8080"` is an integer, `"true"` and `"false"`
  are booleans, an array is split at its `delimiter` (default `,`), an enumeration takes a name. Coercion violations and refinement
  violations (`minimum`, `pattern`, ...) are diagnostics (below), never silent fallbacks.
- A variable that is set but empty **is set**: it is the empty string for a `string`, and a coercion failure for any other
  type. It is not read as "absent".
- A variable whose name is not derived from the schema is ignored: the environment of a process is shared with other programs, so
  a stray `HECATE_DATABSE__PORT` cannot be told from the variables of another tool. The invariant "unknown keys are errors" covers
  every layer that can be enumerated (files and secret files); `Configuration:unused_names()` is not provided (OQ-101).
- The `getenv` option (a function of a name returning a string or `nil`) replaces `os.getenv`, for tests and embedding.

## Secrets

Some keys hold values that must never reach a log: passwords, signing keys, tokens.

- The application lists them in the `secrets` option, as dotted paths of leaves (`{ "database.password" }`). An unknown path is a
  `hecate.core.ArgumentError` at load (a typo must not leave a key unprotected).
- After validation, the value of each declared secret key that is present is wrapped: `Configuration:get` and the root `Section`
  return a **secret object** with the semantics of `hecate.log.Secret` (`tostring` returns `[redacted]`, `reveal()` returns the
  value, and the logging sinks render it as `[redacted]`). The raw value is reachable only through `reveal()`. This is the
  invariant "secrets are never logged": `describe()`, the diagnostics and every error message print `[redacted]` in place of the
  value (a violation says what is wrong, never the value: the messages of `hecate.schema` do not contain it).
- `hecate.config` cannot depend on `hecate.log` (layering). The wrapper is the `wrap_secret` option, a function that takes a value and
  returns the secret object; the kernel passes `hecate.log.Secret` (`kernel.load_configuration`), which the sinks recognise. Without the option, `config` uses
  `package.loaded["hecate.log"].Secret` when that module is already loaded (the same look-up, with no dependency, as OQ-86 for the
  `schema` logger) and otherwise its own `hecate.config.Secret`, a class with the same interface that a `hecate.log` sink does not
  recognise (it still renders `[redacted]` through `tostring`).
- A secret may come from any layer, because forbidding some would break development; the *wrapping* is what protects it.
  The recommended source is a secret file or an environment variable (factor III).

### Secret files

A secret file holds one value, as container platforms mount them (a Docker or Kubernetes secret). For a leaf declared secret:

1. if the variable `<NAME>_FILE` is set, where `<NAME>` is the derived environment variable name, its value is the path of the file;
2. otherwise, if the `secrets_directory` option is set and a file `<secrets_directory>/<NAME>` exists, that file is read.

The content is taken as bytes, without a leading UTF-8 byte order mark, with **one** trailing line end (`\n` or `\r\n`) removed, then converted like an environment
variable (so a secret file can hold an integer). A path named by `<NAME>_FILE` that cannot be read is an error (never ignored); a
missing file of the directory is simply no secret. Secret files exist for secret keys only: a file for any other key is not looked
for. Secret files win over environment variables (layer 5): a mounted secret is more deliberate than an inherited variable.
The `read_file` option (a function of a path returning the content, or `nil` and a message) replaces the file reading, for tests.

## Validation

All layers are merged first, then validated once, with the schema built from the `properties` option and the framework keys:

```lua
local config = require("hecate.config")
local schema = require("hecate.schema")

local configuration = config.load({
  properties = {
    database = schema.object({
      host = schema.default(schema.string(), "localhost"),
      port = schema.default(schema.integer({ minimum = 1, maximum = 65535 }), 5432),
      password = schema.string(),
    }),
  },
  secrets = { "database.password" },
  secrets_directory = "/run/secrets",
})
local port = configuration:get("database.port")
```

- The root is `schema.object(properties)` plus the framework keys `logging` and `limits`. The application must not declare those
  two names (`ArgumentError`). Undeclared properties are rejected at **every** depth: **unknown keys are errors**, with the
  violation code `additional_properties`; the misspelling of a key never goes unnoticed.
- A required property (neither `optional` nor `default`) that no layer supplies is a `required` violation: there is no implicit
  `nil`.
- The declared schema also decides the type of the frozen result: an array is a `List` (also when empty), an object or a map is a
  `Section`. The keys of the application are at most 16 objects deep (`ArgumentError` beyond).
- Defaults come from the schema (`schema.default`, layer 1), so one declaration holds the type, the constraints and the default.
- On failure `config.load` raises one `hecate.core.ConfigurationError` that reports **every** problem found, not the first. Its
  message is, for example:

  ```text
  config.load: invalid configuration (2 problems, environment production)
    database.port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)
    databse: the property is not declared [additional_properties] (config/production.lua)
  ```

  Each line is the dotted path of the key, the message of the violation, its stable code in brackets and the layer
  that supplied the value, or `-` when no layer did (a missing required key; the line then ends with the way out: the files and
  the environment variable that can supply it, and for a secret its `<NAME>_FILE`). The error's `context.violations` is the list of
  `{ path, pointer, code, message, source, hint? }`: `path` is dotted, `pointer` is the JSON Pointer (RFC 6901) of the same key,
  `hint` is the way out of a `required` violation. The value of a secret key is never in it: the message of a violation at a
  secret key says that the value does not conform and not why, since a schema message may quote the value. A value that
  fails to coerce is reported once, not also as missing. The cause of a layer failure (file, secret file)
  is its own `ConfigurationError`, with `context.file`.
- Cross-key rules that a schema cannot express are checked by `config` after the schema and reported the same way (the only one
  today: `logging.file.path` is required when `logging.sinks` contains `file`).

## Immutability and typed access

`config.load` returns a `Configuration`; **the configuration is immutable after boot**:

- every table of the result is a frozen value (`hecate.core` value classes): objects and maps are `Section`s, arrays are `List`s.
  A write raises `hecate.core.ConformanceError`, as for every immutable value. `pairs` iterates a section; `ipairs` and `#` work on
  a list. Reading is by field (`configuration:values().database.port`) or by dotted path.
- `Configuration:get(path)` returns the value of a declared key (a scalar, a secret object, a `Section` or a `List`), or `nil` for
  an optional key that no layer supplied. A path that the schema does not declare is a `hecate.core.ArgumentError`: asking for a key
  that cannot exist is a programmer error, not an absent value. Values are typed by the schema (`get("database.port")` is an
  integer), so no consumer converts or checks again.
- `Configuration:source(path)` names the layer of the value (`schema default` for a default); `Configuration:environment()`;
  `Configuration:describe()` returns a multi-line text, one `path = value (source)` per leaf in key order, in which secrets are
  `[redacted]`: it is the text to log at boot.
- The merge works on copies: the tables returned by the files and the options of the caller are never modified, and nothing the
  caller keeps can change the configuration.

`Section` and `List` have no methods: a key named `get` or `values` in a map must be readable, so they are plain data.

## Logging keys

These keys are declared by `config` (they are part of every configuration) and applied by the kernel when it builds the default
logger (`log.default()`, boot step 1 of the `kernel` item) and the loggers of the framework. This settles the open point of
[logging.md](logging.md) and [OQ-62](../open-questions.md).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `logging.severity` | one of the eight severity names of RFC 5424 | `informational` | the `severity` option of the default logger: the least urgent severity recorded |
| `logging.severities` | map of logger name to severity name | `{}` | named severities: a logger whose `name` is a key of the map takes that severity instead of `logging.severity` |
| `logging.sinks` | array of `console`, `json_lines`, `file` | `{ "console" }` | the sinks of the default logger, in order; an empty array is allowed (the logger records nothing anywhere) |
| `logging.file.path` | string | none | the file of the `file` sink (`FileSink({ path })`); required when `logging.sinks` contains `file` |
| `logging.async` | boolean | `false` | wrap each sink in an `AsyncSink` (needs a running reactor at the first write) |
| `logging.redact` | array of strings | `{}` | field names added to `log.DEFAULT_REDACT` (the built-in list of the default logger, OQ-111): their values become secrets. The list is not replaced; names are matched exactly, case-insensitively, and free text is never scrubbed |

- The names are the glossary's: *severity*, never "level"; *sink*; a *named severity* belongs to a *logger name* (the `name`
  option of `Logger`). The severity enumeration is `emergency`, `alert`, `critical`, `error`, `warning`, `notice`,
  `informational`, `debug`; `info` does not exist (a test keeps the list equal to `log.Severity` when `hecate.log` is loadable).
- A named severity is matched **exactly** against the logger name: there is no inheritance from a dotted prefix (OQ-101). Named
  severities apply to loggers created after boot step 1, as a child logger copies its severity when it is created.
- `console` is the `ConsoleSink` writing to standard output; `json_lines` is the `JsonLinesSink` writing to standard output; `file`
  is the `FileSink`. Standard output is the factor XI ("Logs") choice: the process writes its stream, the platform routes it. The kernel
  supplies `output`; `config` knows no sink class.
- Environment variables: `HECATE_LOGGING__SEVERITY`, `HECATE_LOGGING__SINKS` (comma separated), `HECATE_LOGGING__FILE__PATH`,
  `HECATE_LOGGING__ASYNC`, `HECATE_LOGGING__REDACT`. `logging.severities` is a map and is configured by files only.
- `logging.file.path` is an ordinary string, not a secret.

## Error and request keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `errors.expose_details` | boolean | `false` | bound to the `expose_details` option of the kernel: a 422 entry carries its message and a 500 carries the member `debug` (OQ-112). The kernel logs a `warning` at boot when it is true in the environment `production` |
| `requests.inputs` | `strict` or `lax` | `strict` | bound to the `inputs` option of the dispatcher: policy for undeclared query parameters (OQ-114) |

Environment variables: `HECATE_ERRORS__EXPOSE_DETAILS`, `HECATE_REQUESTS__INPUTS`. The names `errors` and `requests` are
reserved like `logging` and `limits` (`ArgumentError`). `Application({ configuration = configuration })` applies them,
together with `limits.max_depth` and the logging keys; an explicit option of `Application` wins. The generated
`config/development.lua` and `config/test.lua` (a `cli` task) set `expose_details = true` and `inputs = "lax"`, and
`server.grace_timeout` to a low value so that Ctrl+C is quick (OQ-115 (6): 2 seconds, to be confirmed by the owner).

## The server keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `server.grace_timeout` | non-negative finite number (seconds) | `30` | seconds a graceful shutdown lets the requests in flight finish before cancelling them; it must be shorter than the stop timeout of the deployment (`docker stop` waits 10 s by default, Kubernetes 30 s) |
| `server.workers` | integer, at least 1 | `1` | number of worker processes; `1` serves in the process itself, more runs a supervisor in the primary ([ADR 0023](../adr/0023-multi-process-serving.md)) |
| `server.strategy` | `auto`, `reuseport` or `round_robin` | `auto` | how connections reach the workers (ADR 0023, Decision 2); only used when `server.workers` is above 1 |

Environment variables: `HECATE_SERVER__GRACE_TIMEOUT` (text such as `2.5` is coerced to a number),
`HECATE_SERVER__WORKERS` and `HECATE_SERVER__STRATEGY`. A negative value, NaN, infinity or a non-number is a
`ConfigurationError` at load (`server.grace_timeout`); likewise a count below 1 or a name outside the three strategies. The name `server` is reserved like
`logging`, `limits`, `errors` and `requests` (`ArgumentError`). The kernel binds the keys to the `grace_timeout`, `workers` and `strategy` options of `Application`
([OQ-101](../open-questions.md), [OQ-115](../open-questions.md)); `config` only validates and exposes it.

## The limit on nesting depth

| Key | Type | Default | Meaning |
|---|---|---|---|
| `limits.max_depth` | integer, 1 to 1000 | `1000` | the deepest nesting of arrays and objects accepted by `hecate.json` (`decode`, `encode`) and by the depth guard of `hecate.schema` |

This is the single project setting of [OQ-92](../open-questions.md): one number lowers the nesting depth of `json` and `schema`
**together**, so that a value `json.decode` accepts is a value `validate` accepts. The ceiling is 1000, the cap of `json`
(`json.MAX_DEPTH_CEILING`): a project lowers the depth and can never raise it, because deeper recursion can overflow the stack
(a Windows main thread has 1 MiB). The schema refuses a value above 1000 with a violation of code `maximum`; 1000 is repeated in
`config` as a constant, because `config` does not depend on `json`, and a test compares it with `json.MAX_DEPTH_CEILING`.

`config` only validates and exposes the value (`configuration:get("limits.max_depth")`, environment variable
`HECATE_LIMITS__MAX_DEPTH`). **Applying it:** `json` now has a setter and `schema` reads the value it holds (added by the `kernel` item; the kernel
calls it at boot). The setter is a process-wide `json.set_max_depth(n)` (lowering only, refusing a value above `json.MAX_DEPTH_CEILING`, reading back
through `json.DEFAULT_MAX_DEPTH`).

## Errors and messages

| Class | When |
|---|---|
| `hecate.core.ConfigurationError` | any invalid configuration: unreadable or invalid file, unknown key, wrong type, missing required key, colliding environment variable names, a `file` sink without path |
| `hecate.core.ArgumentError` | a wrong option of `load` (unknown option, bad `env_prefix`, `properties` that redeclare `logging`, `limits`, `errors`, `requests` or `server`, an unknown secret path); `get` of an undeclared path |
| `hecate.core.ConformanceError` | a write to a frozen section or list |

Messages follow [coding-standards.md](coding-standards.md#errors): the qualified prefix (`config.load: ...`), the offending value and
the expected one, and never a secret value.

## Concurrency and suspension

`config.load` reads files with `io` and blocks: it runs before the reactor starts, at boot, and nothing in the package suspends or
needs a reactor. A `Configuration` is immutable, so it is safe to share between computations without synchronisation. Workers
(ADR 0023) each load their configuration from the same sources.

## Testing guidance

- Pass `getenv` and `read_file` instead of touching the real environment or disk.
- Assert on `ConfigurationError.context.violations` (paths and codes), not on the message text alone.
- A secret: render `describe()`, the error message and `tostring` of the section, and search the output for the value.

## Open points

- [OQ-101](../open-questions.md): conservative choices of the first implementation, and the setter that `limits.max_depth` needs in `json` and `schema`.
