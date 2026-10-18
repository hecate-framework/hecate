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

- every stream is `<close>`-able (`close`, `__close`, `is_closed`: a generic test walks every class)
- a closed stream, reader or writer raises `reactor.TransportError` with errno `EBADF` and a stable `context.operation`
- partial reads/writes never leak to callers of buffered APIs (a failed or cancelled flush poisons the writer; a cancelled read loses nothing)
- net-level options are validated against an allow-list before anything is resolved, and the error names the net function
- TLS verification is on and cannot be disabled (OQ-41); the system store is trusted by default, `ca_pem` adds anchors (ADR 0024)

## Test strategy

- loopback integration tests on three platforms
- TLS against a local test CA
- fault injection: resets, half-close, slow peers

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- `net.listen("localhost", ...)` binds only the first address the resolver lists; tests pin `family = "inet"` or use numeric addresses
- `UdpSocket:send_to` takes a numeric address only (a name raises `ArgumentError` pointing to `net.resolve`)
- tests may require `luv` to spy on handles; `src` never may (`check-boundaries`)
- the unit tests wrap `reactor.resolve` and `reactor.tcp_connect` to script multi-address connects: restore them in every path

- Windows socket error codes differ
- Nagle and keep-alive defaults
- certificate stores differ per platform: the default path goes through the operating system's verifier (ADR 0024), hermetic tests use `system_roots = false`
- the TLS tests fail, not skip, when `HECATE_REQUIRE_TLS=1` and the native module is missing
- use futures and joins, not `reactor.sleep`, to order events in tests

## Standards

- RFC 8446 (TLS 1.3)
- RFC 6125 (service identity)
