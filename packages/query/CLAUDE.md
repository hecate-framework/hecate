# Agent context — `hecate.query`

You are working inside `packages/query`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-query`.

## Purpose

Query builder using relational-algebra vocabulary (projection, selection, join, rename, union) and the database-schema definition API, independent of any dialect.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0004-academic-vocabulary.md`, `docs/adr/0011-orm-data-mapper.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core` only (the translators to a dialect live in `hecate.sql`, which depends on `query`; ADR 0026).
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: object mapping (see `orm`); translation to a dialect and execution (see `sql`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- expression trees are immutable values; building one never touches a dialect or a data source
- the database-schema (DDL) definition API is part of this package, not of `migration` or `sql`

## Test strategy

- unit tests of the expression tree and of the database-schema definition API; the golden SQL per dialect lives in `sql`

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- `selection` means SQL `WHERE`, `projection` means SQL `SELECT`; document it everywhere

## Standards

- Codd, relational algebra (1970)
- SQL dialects of PostgreSQL, MySQL/MariaDB, SQLite, SQL Server
