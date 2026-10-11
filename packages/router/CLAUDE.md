# Agent context — `hecate.router`

You are working inside `packages/router`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-router`.

## Purpose

Radix-tree router over URI templates (RFC 6570 level-1 subset) with 404/405 handling and reverse routing.

## Read before changing anything

- Specification: `docs/architecture/http-and-routing.md`
- Decisions: `docs/adr/0006-declarative-routes-as-runtime-data.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: parameter validation (done by kernel with `schema`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- matching cost independent of the number of routes for static prefixes
- ambiguous route tables are rejected at boot with a precise diagnostic

## Test strategy

- property tests: generated route sets
- benchmarks against large route tables

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- percent-encoding and normalisation
- trailing slash policy (explicit, configurable)

## Standards

- RFC 6570 (URI Template)
- RFC 3986 (URI)
