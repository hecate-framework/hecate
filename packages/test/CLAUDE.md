# Agent context — `hecate.test`

You are working inside `packages/test`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-test`.

## Purpose

xUnit test framework running inside the reactor: cases, suites, fixtures, assertions, in-process HTTP client, contract conformance, property-based testing, coverage.

## Read before changing anything

- Specification: `docs/architecture/testing.md`
- Decisions: `docs/adr/0008-own-test-framework.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.log`, `hecate.schema`, `hecate.kernel`, `hecate.openapi`, `hecate.json`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: browser testing.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- a failing test never affects another test
- same API as the bootstrap harness for migration (ADR 0008)

## Test strategy

- self-hosted: the framework tests itself
- reporter golden files

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- debug hooks slow coverage runs; keep coverage optional

## Standards

- xUnit patterns (Meszaros 2007)
- QuickCheck (Claessen & Hughes 2000)
- TAP 14
- JUnit XML
