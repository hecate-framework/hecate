# Agent context — `hecate.websocket`

You are working inside `packages/websocket`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-websocket`.

## Purpose

WebSocket protocol (RFC 6455) server and client integrated with the kernel.

## Read before changing anything

- Specification: `docs/roadmap.md`
- Decisions: none specific
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.http`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: none.
- Out of scope: Socket.IO.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- Autobahn test suite passes

## Test strategy

- Autobahn TestSuite

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- masking rules
- back-pressure

## Standards

- RFC 6455
- RFC 7692 (permessage-deflate)
