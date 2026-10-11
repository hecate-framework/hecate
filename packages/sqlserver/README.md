# `hecate-sqlserver`

> Microsoft SQL Server driver implementing TDS in Lua.

| | |
|---|---|
| Module | `hecate.sqlserver` |
| Rock | `hecate-sqlserver` |
| Layer | Data |
| Roadmap phase | 5 |
| Status | planned — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`sql`](../sql) |
| Used by | — |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-sqlserver`](../../.claude/agents/pkg-sqlserver.md) |
| Repository | read-only mirror `hecate-framework/hecate-sqlserver`, generated from this directory (ADR 0017) |

## Responsibilities

- login, TLS, SQL batches, RPC, prepared statements
- type codecs

## Non-goals

- Windows integrated authentication initially

## Standards and references

- MS-TDS

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/sqlserver/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
