# Agent context — `hecate.mysql`

You are working inside `packages/mysql`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-mysql`.

## Purpose

MySQL and MariaDB driver implementing the client/server protocol in Lua, with dialect detection.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.sql`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none (crypto via TLS binding).
- Out of scope: X Protocol.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- implements `sql` interfaces and passes the conformance suite

## Test strategy

- integration against MySQL and MariaDB, two versions each

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- charset/collation negotiation
- zero dates

## Standards

- MySQL client/server protocol
- MariaDB protocol extensions
