# Agent context — `hecate.sql`

You are working inside `packages/sql`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-sql`.

## Purpose

Driver-agnostic SQL interfaces (drivers, connections, prepared statements, transactions and savepoints, connection pool, type mapping, instrumentation) and the translators from the query expression tree to each SQL dialect.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.log`, `hecate.query` (the translators from the expression tree to a dialect live here; ADR 0026).
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: building queries and defining the database schema (see `query`); transport and wire protocols (see the drivers).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- parameters are always bound, never interpolated
- connections returned to the pool are reset
- transactions are `<close>`-able and roll back on error
- translation is deterministic and identifiers are quoted per dialect

## Test strategy

- conformance suite every driver must pass
- golden SQL per dialect for every translator

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- pool exhaustion under cancellation

## Standards

- ISO/IEC 9075 (SQL)
- SQLSTATE codes
