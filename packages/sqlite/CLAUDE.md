# Agent context — `hecate.sqlite`

You are working inside `packages/sqlite`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-sqlite`.

## Purpose

SQLite driver: C binding to the vendored amalgamation, executed on the libuv thread pool.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.sql`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: SQLite amalgamation (public domain).
- Out of scope: SQLite extensions loading by default.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- Lua state is never touched from pool threads

## Test strategy

- conformance suite
- sanitizer builds

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- one connection per thread rules
- busy timeouts

## Standards

- SQLite C API
