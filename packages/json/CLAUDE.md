# Agent context — `hecate.json`

You are working inside `packages/json`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-json`.

## Purpose

Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and precise error positions.

## Read before changing anything

- Specification: `docs/architecture/schemas-and-contracts.md`
- Decisions: ADR 0020 (yyjson decoder, native encoder), ADR 0021 (Rust as a build-time tool); owner decisions OQ-48, OQ-49, OQ-51 in `docs/open-questions.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: C decoder over vendored yyjson (`csrc/`), Rust encoder (`native/`); the pure-Lua reference backend is the fallback and the test oracle, and every native answer must match it.
- Out of scope: schema validation (see `schema`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- round-trip stability for every value it can encode
- never produces invalid UTF-8
- depth and size limits configurable, with safe defaults

## Test strategy

- JSONTestSuite conformance
- differential tests and fuzzing of the native backends against the reference backend, JSONTestSuite corpus on both backends (`lua tools/run.lua fetch-fixtures json`)
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
