# `hecate-mongodb`

> MongoDB driver (OP_MSG + BSON) and document mapper sharing the unit-of-work vocabulary.

| | |
|---|---|
| Module | `hecate.mongodb` |
| Rock | `hecate-mongodb` |
| Layer | Data |
| Roadmap phase | 5 |
| Status | planned — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net) |
| Used by | — |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-mongodb`](../../.claude/agents/pkg-mongodb.md) |
| Repository | read-only mirror `hecate-framework/hecate-mongodb`, generated from this directory (ADR 0017) |

## Responsibilities

- BSON codec
- CRUD, aggregation, transactions, change streams
- document mapper

## Non-goals

- GridFS initially

## Standards and references

- MongoDB wire protocol (OP_MSG)
- BSON specification
- SCRAM-SHA-256

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/mongodb/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
