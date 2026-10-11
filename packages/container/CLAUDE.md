# Agent context — `hecate.container`

You are working inside `packages/container`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-container`.

## Purpose

Inversion-of-control container: bindings, lifetimes (singleton, scoped, transient), constructor injection, cycle detection at boot.

## Read before changing anything

- Specification: `docs/architecture/http-and-routing.md`
- Decisions: `docs/adr/0007-object-model.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: service location from arbitrary code (anti-pattern).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- no resolution failure can happen at request time for a validated graph

## Test strategy

- graph validation cases
- scoped lifetime across fork

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- singleton depending on scoped service (must be rejected)

## Standards

- Fowler, *Inversion of Control Containers and the Dependency Injection pattern* (2004)
- Seemann, composition root (2011)
