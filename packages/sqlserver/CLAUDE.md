# Agent context — `hecate.sqlserver`

You are working inside `packages/sqlserver`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-sqlserver`.

## Purpose

Microsoft SQL Server driver implementing TDS in Lua.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.sql`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: Windows integrated authentication initially.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- implements `sql` interfaces and passes the conformance suite

## Test strategy

- SQL Server 2022 container

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- TLS inside TDS pre-login

## Standards

- MS-TDS
