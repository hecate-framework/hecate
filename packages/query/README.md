# `hecate-query`

> Query builder using relational-algebra vocabulary (projection, selection, join, rename, union) rendered per SQL dialect.

| | |
|---|---|
| Module | `hecate.query` |
| Rock | `hecate-query` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`sql`](../sql) |
| Used by | `migration`, `orm` |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0011](../../docs/adr/0011-orm-data-mapper.md) |
| Agent | [`pkg-query`](../../.claude/agents/pkg-query.md) |
| Repository | read-only mirror `hecate-framework/hecate-query`, generated from this directory (ADR 0017) |

## Responsibilities

- immutable query values
- dialect renderers
- schema-definition API used by `migration`
- relational algebra ↔ SQL correspondence table in docs

## Non-goals

- object mapping (see `orm`)

## Standards and references

- Codd, relational algebra (1970)
- SQL dialects of PostgreSQL, MySQL/MariaDB, SQLite, SQL Server

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/query/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
