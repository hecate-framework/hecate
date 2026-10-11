# `hecate-sqlite`

> SQLite driver: C binding to the vendored amalgamation, executed on the libuv thread pool.

| | |
|---|---|
| Module | `hecate.sqlite` |
| Rock | `hecate-sqlite` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`sql`](../sql) |
| Used by | — |
| Native code | SQLite amalgamation (public domain) |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-sqlite`](../../.claude/agents/pkg-sqlite.md) |
| Repository | read-only mirror `hecate-framework/hecate-sqlite`, generated from this directory (ADR 0017) |

## Responsibilities

- connections executed on worker threads without blocking the reactor
- prepared statements, transactions, WAL mode defaults
- in-memory databases for tests

## Non-goals

- SQLite extensions loading by default

## Standards and references

- SQLite C API

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/sqlite/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
