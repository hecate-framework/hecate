# Agent context — `hecate`

You are working inside `packages/hecate`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-hecate`.

## Purpose

Meta-rock `hecate`: depends on the standard edition and provides the `hecate` meta-module re-exporting the framework surface.

## Read before changing anything

- Specification: `docs/architecture/overview.md`
- Decisions: `docs/adr/0005-single-brand-monorepo-lockstep-versioning.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.json`, `hecate.log`, `hecate.http`, `hecate.schema`, `hecate.router`, `hecate.container`, `hecate.config`, `hecate.kernel`, `hecate.openapi`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: code of its own beyond re-exports.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- version identical to all other packages

## Test strategy

- re-export completeness test

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- accidental re-export of internals

## Standards

- —
