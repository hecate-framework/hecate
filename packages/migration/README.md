# `hecate-migration`

> Versioned, reversible schema migrations with checksums and CLI integration.

| | |
|---|---|
| Module | `hecate.migration` |
| Rock | `hecate-migration` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`sql`](../sql), [`query`](../query), [`log`](../log) |
| Used by | `cli` |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0011](../../docs/adr/0011-orm-data-mapper.md) |
| Agent | [`pkg-migration`](../../.claude/agents/pkg-migration.md) |
| Repository | read-only mirror `hecate-framework/hecate-migration`, generated from this directory (ADR 0017) |

## Responsibilities

- migration files with `up`/`down`
- transactional DDL when supported
- applied-migration relation with checksums
- status, apply, rollback, new
- later: diff from ORM metadata

## Non-goals

- data seeding framework (scripts cover it)

## Standards and references

- —

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/migration/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
