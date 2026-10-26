# `hecate-mysql`

> MySQL and MariaDB driver implementing the client/server protocol in Lua, reporting a descriptor of its dialect, version and capabilities.

| | |
|---|---|
| Module | `hecate.mysql` |
| Rock | `hecate-mysql` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`sql`](../sql) |
| Used by | — |
| Native code | none (crypto via TLS binding) |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-mysql`](../../.claude/agents/pkg-mysql.md) |
| Repository | read-only mirror `hecate-framework/hecate-mysql`, generated from this directory (ADR 0017) |

## Responsibilities

- handshake, `caching_sha2_password`, `mysql_native_password`, TLS
- text and binary protocols, prepared statements
- MariaDB detection and differences, reported through the descriptor (dialect, server version, capabilities) that `sql` uses to choose a translator (ADR 0026)

## Non-goals

- X Protocol

## Standards and references

- MySQL client/server protocol
- MariaDB protocol extensions

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/mysql/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
