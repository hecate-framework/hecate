# Agent context — `hecate.postgresql`

You are working inside `packages/postgresql`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-postgresql`.

## Purpose

PostgreSQL driver implementing the frontend/backend protocol v3 in Lua.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.sql`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none (crypto via TLS binding).
- Out of scope: logical replication (later).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- implements `sql` interfaces and passes the conformance suite

## Test strategy

- integration against the two latest major versions

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- `ParameterStatus` and session state
- pipelining errors

## Standards

- PostgreSQL protocol v3
- RFC 5802/7677 (SCRAM-SHA-256)
