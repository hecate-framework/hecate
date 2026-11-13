# `hecate-config`

> Layered configuration (defaults, environment files, environment variables, secrets) validated by schemas at boot.

| | |
|---|---|
| Module | `hecate.config` |
| Rock | `hecate-config` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | alpha — implemented in Phase 2: layers, environment variables, secret files, validation at boot, immutable `Configuration`, logging keys and `limits.max_depth` |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`schema`](../schema) |
| Used by | `hecate`, `kernel` |
| Native code | none |
| Specification | [configuration.md](../../docs/architecture/configuration.md) (boot sequence: [overview.md](../../docs/architecture/overview.md)) |
| Decisions | none specific; conservative choices in OQ-101 |
| Agent | [`pkg-config`](../../.claude/agents/pkg-config.md) |
| Repository | read-only mirror `hecate-framework/hecate-config`, generated from this directory (ADR 0017) |

## Responsibilities

- layers: `config/default.lua`, `config/<environment>.lua`, environment variables, secret files
- validation against declared schemas with precise diagnostics
- typed access
- secrets never logged

## Non-goals

- remote configuration services (later, by a separate package)

## Standards and references

- The Twelve-Factor App (configuration)

## Public API

`local config = require("hecate.config")`

- `config.load(options)`: reads the layers (schema defaults, `config/default.lua`, `config/<environment>.lua`, environment variables, secret files), merges them, validates once and returns a `Configuration`. Options (`hecate.config.LoadOptions`): `properties` (the application keys, as schemas), `environment`, `directory`, `env_prefix`, `secrets`, `secrets_directory`, `wrap_secret`, `getenv`, `read_file` (the last two are hooks for tests and embedding). Raises `ConfigurationError` listing every violation (`context.violations`: `path` dotted, `pointer`, `code`, `message`, `source`, `hint`; a non-string key or a table mixing items and named keys in a file is a `type` violation at that key) and `ArgumentError` for wrong options (`secrets` must be a list; a property name contains no `.`, at any depth).
- `Configuration`: an immutable object (a value class, compared by identity; a write raises `ConformanceError`). `get(path)` (typed value by dotted path; the path is validated against the schema, an undeclared or malformed path is an `ArgumentError`; use `values()` and read by field to destructure), `source(path)` (the layer that won; a section created by environment variables or secret files names that layer), `values()` (the root `Section`), `environment()`, `describe()` (exactly one line per leaf, control characters escaped as `\n`, `\r`, `\ddd`, secrets redacted).
- `config.Section`, `config.List`: the frozen objects, maps and arrays of a configuration (writes raise `ConformanceError`).
- `config.Secret`: fallback secret object with the interface of `hecate.log.Secret` (immutable: the value cannot be replaced).
- `config.variable_name(prefix, segments)`: the environment variable of a key (`ArgumentError` for a prefix that `env_prefix` would refuse, or segments that are not a non-empty list of non-empty strings). `config.SEVERITIES`, `config.MAX_DEPTH_CEILING`: constants of the framework keys.
- Framework keys, declared by every configuration: `logging.severity`, `logging.severities`, `logging.sinks`, `logging.file.path`, `logging.async`, `logging.redact`, `limits.max_depth` (1 to 1000), `errors.expose_details`, `requests.inputs` and `server.grace_timeout` (seconds, at least 0, default 30; `HECATE_SERVER__GRACE_TIMEOUT`), `server.workers` (integer at least 1, default 1; `HECATE_SERVER__WORKERS`) and `server.strategy` (`auto`, `reuseport` or `round_robin`, default `auto`; `HECATE_SERVER__STRATEGY`). The names `logging`, `limits`, `errors`, `requests` and `server` are reserved.

Environment: the `environment` option, else `HECATE_ENV` (`<PREFIX>_ENV`), else `production`; `config/production.lua` may be absent when the environment is implicit. Limits: `config` does not apply `limits.max_depth` itself: `kernel.Application` applies it at boot (`json.set_max_depth`, read by `schema`). Stray environment variables cannot be detected (Lua cannot list the environment). `config` applies no logging key itself: the kernel does.

Documentation: the how-to [Configure an application](../../website/en/how-to/configure-an-application.md) and the tested example in `examples/`.

## Layout

```text
src/hecate/config/init.lua   public entry point
src/hecate/config/load.lua, declaration.lua, configuration.lua, values.lua, secret.lua
tests/unit/  tests/integration/  tests/support/
examples/
```
