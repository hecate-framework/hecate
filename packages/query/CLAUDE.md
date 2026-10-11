# Agent context — `hecate.query`

You are working inside `packages/query`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-query`.

## Purpose

Query builder using relational-algebra vocabulary (projection, selection, join, rename, union) rendered per SQL dialect.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0004-academic-vocabulary.md`, `docs/adr/0011-orm-data-mapper.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.sql`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: object mapping (see `orm`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- rendering is deterministic
- identifiers quoted per dialect

## Test strategy

- golden SQL per dialect
- execution tests on all drivers

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- `selection` means SQL `WHERE`, `projection` means SQL `SELECT`; document it everywhere

## Standards

- Codd, relational algebra (1970)
- SQL dialects of PostgreSQL, MySQL/MariaDB, SQLite, SQL Server
