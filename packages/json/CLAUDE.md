# Agent context — `hecate.json`

You are working inside `packages/json`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-json`.

## Purpose

Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and streaming.

## Read before changing anything

- Specification: `docs/architecture/schemas-and-contracts.md`
- Decisions: none specific
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: C codec (OQ-5).
- Out of scope: schema validation (see `schema`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- round-trip stability for every value it can encode
- never produces invalid UTF-8
- depth and size limits configurable, with safe defaults

## Test strategy

- JSONTestSuite conformance
- fuzzing (C)
- property tests: decode(encode(x)) == x

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- empty table: object or array?
- NaN/Infinity are not JSON
- large integers beyond 2^53 in other languages

## Standards

- RFC 8259
- RFC 6901 (JSON Pointer)
- I-JSON, RFC 7493
