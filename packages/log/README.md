# `hecate-log`

> Structured logging with RFC 5424 severities, per-scope context and pluggable sinks.

| | |
|---|---|
| Module | `hecate.log` |
| Rock | `hecate-log` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | step 1: severities, records, `Logger` with context, in-memory and JSON lines sinks, `Secret`; console and file sinks, `LimitedSink` (sampling and rate limiting); asynchronous flushing blocked on `reactor` |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`json`](../json) |
| Used by | `cli`, `hecate`, `http`, `kernel`, `migration`, `sql`, `test` |
| Native code | none |
| Specification | [overview.md](../../docs/architecture/overview.md) |
| Decisions | [ADR 0004](../../docs/adr/0004-academic-vocabulary.md) |
| Agent | [`pkg-log`](../../.claude/agents/pkg-log.md) |
| Repository | read-only mirror `hecate-framework/hecate-log`, generated from this directory (ADR 0017) |

## Responsibilities

- `Logger` with `emergency` … `debug`
- context propagation through reactor scopes (request id)
- sinks: console (human), JSON lines, file; asynchronous flushing
- sampling and rate limiting

## Non-goals

- metrics and tracing (later, OpenTelemetry-compatible package)

## Standards and references

- RFC 5424 severities

## Public API

```lua
local log = require("hecate.log")
```

| Name | Description |
|---|---|
| `log.Severity` | Enumeration of the eight RFC 5424 severities, `emergency` to `debug` (`informational`, no alias). |
| `log.severity_code(severity)` | RFC 5424 numerical code, 0 to 7. |
| `log.Logger(options?)` | Options: `level` (default `informational`), `sinks`, `name`, `context`, `context_provider`, `clock`. Methods `emergency` ... `debug` `(message, fields?)`, `log(severity, message, fields?)`, `is_enabled`, `set_level`, `level`, `add_sink`, `with_context(fields)`, `failures()`. A call below the threshold builds no record; a sink that raises never fails the caller. |
| `log.Record` | What sinks receive: `severity`, `message`, `fields`, `context`, `timestamp`, `logger`. |
| `log.MemorySink(options?)` | Keeps records (`records()`, `clear()`, `dropped()`, option `capacity`). |
| `log.JsonLinesSink(options)` | Writes one JSON object per record to `options.output(line)`; renders secrets as `[redacted]`. |
| `log.ConsoleSink(options)` | Writes `timestamp SEVERITY [logger] message key=value ...` to `options.output(line)`; secrets redacted, control characters escaped. |
| `log.FileSink(options)` | Appends JSON lines to `options.path` (synchronous); `close()`. |
| `log.Secret(value)` | Marks a value that no sink renders; `reveal()` returns it. |

A sink is any object with a synchronous `write(record)` that does not suspend. The context does not follow
fork and join by itself yet: pass the child logger from `with_context` to forked computations (OQ-55).

## Layout (once implemented)

```text
src/hecate/log/init.lua   public entry point (one file per class beside it, `internal/` for helpers)
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
