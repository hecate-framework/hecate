# `hecate-orm`

> Object-relational mapper: Data Mapper with Unit of Work, Identity Map, associations and repositories.

| | |
|---|---|
| Module | `hecate.orm` |
| Rock | `hecate-orm` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`sql`](../sql), [`query`](../query), [`schema`](../schema) |
| Used by | — |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0007](../../docs/adr/0007-object-model.md), [ADR 0011](../../docs/adr/0011-orm-data-mapper.md) |
| Agent | [`pkg-orm`](../../.claude/agents/pkg-orm.md) |
| Repository | read-only mirror `hecate-framework/hecate-orm`, generated from this directory (ADR 0017) |

## Responsibilities

- entity metadata (relation, attributes, keys, associations)
- unit of work: change tracking, ordered flush, single transaction
- identity map per unit of work
- repositories
- loading: eager loading is explicit and recommended; lazy loading suspends transparently, and the ORM warns in development when it detects N+1 queries (extra queries caused by accessing a relation that the first query did not load)
- integration with `schema` for representations

## Non-goals

- Active Record API

## Standards and references

- Fowler, *Patterns of Enterprise Application Architecture* (2002)
- Evans, *Domain-Driven Design* (2003)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/orm/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
