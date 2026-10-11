# `hecate-redis`

> Redis client (RESP3 with RESP2 fallback), compatible with Valkey and KeyDB.

| | |
|---|---|
| Module | `hecate.redis` |
| Rock | `hecate-redis` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net) |
| Used by | — |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-redis`](../../.claude/agents/pkg-redis.md) |
| Repository | read-only mirror `hecate-framework/hecate-redis`, generated from this directory (ADR 0017) |

## Responsibilities

- commands, pipelining, transactions (`MULTI`/`EXEC`)
- publish/subscribe
- Lua scripts
- connection pool, TLS, ACL authentication
- cluster and sentinel (later)

## Non-goals

- object mapping

## Standards and references

- RESP3 specification

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/redis/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
