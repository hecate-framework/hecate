# Agent context — `hecate.http`

You are working inside `packages/http`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-http`.

## Purpose

HTTP/1.1 server and client with a message model following RFC 9110 semantics.

## Read before changing anything

- Specification: `docs/architecture/http-and-routing.md`
- Decisions: `docs/adr/0003-transparent-structured-concurrency.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`, `hecate.net`, `hecate.json`, `hecate.log`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: llhttp binding (OQ-6).
- Out of scope: routing (see `router`); HTTP/2 and WebSocket in early phases.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- request smuggling defences (conflicting Content-Length/Transfer-Encoding rejected)
- every limit has a safe default
- one coroutine and one scope per request

## Test strategy

- conformance against RFC test vectors
- fuzzing the parser wrapper
- load tests in benchmarks

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- slowloris
- header folding
- `Expect: 100-continue`
- HEAD responses without content

## Standards

- RFC 9110 (semantics)
- RFC 9112 (HTTP/1.1)
- RFC 6265 (cookies)
- RFC 7578 (multipart/form-data)
