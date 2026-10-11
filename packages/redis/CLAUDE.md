# Agent context — `hecate.redis`

You are working inside `packages/redis`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-redis`.

## Purpose

Redis client (RESP3 with RESP2 fallback), compatible with Valkey and KeyDB.

## Read before changing anything

- Specification: `docs/architecture/data-access.md`
- Decisions: `docs/adr/0014-wire-protocol-drivers-in-lua.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: object mapping.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- pipelined replies always matched to requests

## Test strategy

- integration against Redis and Valkey

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- push messages in RESP3

## Standards

- RESP3 specification
