# Agent context — `hecate.orm`

You are working inside `packages/orm`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-orm`.

## Purpose

Object-relational mapper: Data Mapper with Unit of Work, Identity Map, associations and repositories.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0004-academic-vocabulary.md`, `docs/adr/0007-object-model.md`, `docs/adr/0011-orm-data-mapper.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.sql`, `hecate.query`, `hecate.schema`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: Active Record API.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- entities never reference the database
- a unit of work is bound to one reactor scope

## Test strategy

- all relational drivers
- N+1 detection tests

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- identity map across concurrent coroutines

## Standards

- Fowler, *Patterns of Enterprise Application Architecture* (2002)
- Evans, *Domain-Driven Design* (2003)
