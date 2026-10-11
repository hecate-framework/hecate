# Agent context — `hecate.openapi`

You are working inside `packages/openapi`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-openapi`.

## Purpose

OpenAPI 3.1 document assembly from the route table, schemas and project settings; served endpoint, export, lint and breaking-change diff.

## Read before changing anything

- Specification: `docs/architecture/schemas-and-contracts.md`
- Decisions: `docs/adr/0006-declarative-routes-as-runtime-data.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.schema`, `hecate.router`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: client code generation (later).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- deterministic output (stable ordering) for diffs
- every route appears; undocumented responses are lint errors

## Test strategy

- golden files
- validation of output against the official OpenAPI 3.1 schema

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- schema component naming collisions

## Standards

- OpenAPI 3.1
- JSON Schema 2020-12
