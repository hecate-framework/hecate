# Agent context — `hecate.mongodb`

You are working inside `packages/mongodb`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-mongodb`.

## Purpose

MongoDB driver (OP_MSG + BSON) and document mapper sharing the unit-of-work vocabulary.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: GridFS initially.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- BSON round-trip fidelity

## Test strategy

- integration against two server versions

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- ordered document keys

## Standards

- MongoDB wire protocol (OP_MSG)
- BSON specification
- SCRAM-SHA-256
