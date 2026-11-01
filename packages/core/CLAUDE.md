# Agent context — `hecate.core`

You are working inside `packages/core`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-core`.

## Purpose

Object model (classes, traits, interfaces), error hierarchy, enumerations, value objects and Lua-version compatibility shims.

## Read before changing anything

- Specification: `docs/architecture/object-model.md`
- Decisions: `docs/adr/0001-lua-5.5-as-sole-target.md`, `docs/adr/0004-academic-vocabulary.md`, `docs/adr/0007-object-model.md`, `docs/adr/0018-error-signalling.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: none (only the Lua standard library).
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: multiple inheritance; runtime-enforced visibility (convention + linter only); any I/O.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- method lookup after finalisation is one table access (flattened methods)
- no other package defines a class mechanism
- finalisation errors name the class, the missing/conflicting member and its origin

## Test strategy

- exhaustive unit tests of composition rules and conflicts
- metamethod inheritance matrix
- micro-benchmarks of method dispatch versus raw metatables

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- `__index` functions on hot paths are forbidden after finalisation
- `__gc` order is not guaranteed; never rely on it for correctness
- LuaLS must infer `---@class Name : Superclass` from the chosen declaration spelling

## Standards

- Schärli et al., *Traits: Composable Units of Behaviour* (2003)
