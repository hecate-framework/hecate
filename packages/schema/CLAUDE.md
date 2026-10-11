# Agent context — `hecate.schema`

You are working inside `packages/schema`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-schema`.

## Purpose

Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.

## Read before changing anything

- Specification: `docs/architecture/schemas-and-contracts.md`
- Decisions: `docs/adr/0004-academic-vocabulary.md`, `docs/adr/0006-declarative-routes-as-runtime-data.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: persistence metadata (see `orm`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- schemas are immutable values
- compiled validators: no interpretation overhead per request
- emitted JSON Schema validates exactly what Lua validation accepts

## Test strategy

- JSON Schema official test suite (supported subset)
- differential tests: Lua validation versus emitted JSON Schema

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- integer versus number distinction
- `additional_properties` default
- recursive schemas

## Standards

- JSON Schema 2020-12
- RFC 6901
- RFC 3339 (date-time)
