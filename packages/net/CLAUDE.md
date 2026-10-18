# Agent context — `hecate.net`

You are working inside `packages/net`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-net`.

## Purpose

TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

## Read before changing anything

- Specification: `docs/architecture/concurrency.md`
- Decisions: `docs/adr/0002-libuv-via-luv.md`, `docs/adr/0003-transparent-structured-concurrency.md`,
  `docs/adr/0021-rust-native-modules.md`; open questions OQ-28, OQ-30, OQ-31, OQ-32, OQ-41, OQ-42
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`, `hecate.reactor`.
  Anything else requires an ADR; `check-boundaries` fails otherwise. `net` never requires
  `luv`: all transport goes through `hecate.reactor` (OQ-28).
- Native code: the Rust module `native/` (rustls through mlua, ADR 0021, OQ-41), built with
  `lua tools/run.lua build-native net`; no `unsafe`, warnings and clippy denied.
- Out of scope: application protocols (HTTP lives in `http`).
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- every stream is `<close>`-able
- partial reads/writes never leak to callers of buffered APIs
- TLS verification is on and cannot be disabled (OQ-41); trust anchors are passed as `ca_pem`

## Test strategy

- loopback integration tests on three platforms
- TLS against a local test CA
- fault injection: resets, half-close, slow peers

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- Windows socket error codes differ
- Nagle and keep-alive defaults
- certificate stores differ per platform: no system store yet, `ca_pem` is required (OQ-41)
- the TLS tests fail, not skip, when `HECATE_REQUIRE_TLS=1` and the native module is missing
- use futures and joins, not `reactor.sleep`, to order events in tests

## Standards

- RFC 8446 (TLS 1.3)
- RFC 6125 (service identity)
