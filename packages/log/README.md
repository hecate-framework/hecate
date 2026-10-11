# `hecate-log`

> Structured logging with RFC 5424 severities, per-scope context and pluggable sinks.

| | |
|---|---|
| Module | `hecate.log` |
| Rock | `hecate-log` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | specified — no code yet |
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

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/log/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
