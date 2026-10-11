# Agent context — `hecate.migration`

You are working inside `packages/migration`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-migration`.

## Purpose

Versioned, reversible schema migrations with checksums and CLI integration.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0011-orm-data-mapper.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.sql`, `hecate.query`, `hecate.log`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: data seeding framework (scripts cover it).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- edited applied migrations are detected

## Test strategy

- all drivers

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- MySQL implicit commits on DDL

## Standards

- —
