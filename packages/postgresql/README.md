# `hecate-postgresql`

> PostgreSQL driver implementing the frontend/backend protocol v3 in Lua.

| | |
|---|---|
| Module | `hecate.postgresql` |
| Rock | `hecate-postgresql` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`sql`](../sql) |
| Used by | — |
| Native code | none (crypto via TLS binding) |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-postgresql`](../../.claude/agents/pkg-postgresql.md) |
| Repository | read-only mirror `hecate-framework/hecate-postgresql`, generated from this directory (ADR 0017) |

## Responsibilities

- startup, SCRAM-SHA-256, TLS
- simple and extended query protocols, prepared statements
- binary/text type codecs
- COPY
- LISTEN/NOTIFY
- cancellation requests

## Non-goals

- logical replication (later)

## Standards and references

- PostgreSQL protocol v3
- RFC 5802/7677 (SCRAM-SHA-256)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/postgresql/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
