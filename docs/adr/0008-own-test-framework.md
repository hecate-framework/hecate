# 0008 — A dedicated test framework running inside the reactor

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** test, and every package's test suite
- **Related:** [testing.md](../architecture/testing.md)

## Context

Hecate code suspends transparently on I/O; tests must therefore run inside reactor
coroutines. Existing runners (busted) are not reactor-aware, follow BDD vocabulary and
do not know about contracts, schemas or the kernel.

## Options considered

1. **busted + adapters.** Mature, but a second idiom next to Hecate's object model; async
   integration by wrapping every test.
2. **`hecate.test`**: xUnit-style test cases built on the object model, executed inside
   the reactor, with an in-process HTTP client, fixtures, contract conformance and
   property-based testing.

## Decision

Option 2, xUnit vocabulary (*test case*, *test suite*, *fixture*, *assertion*,
*runner*). Until `hecate.test` exists (Phase 3), packages use a **minimal bootstrap
harness** living in `tools/harness/` (Phase 0) with an API compatible with the
eventual one (`test_*` methods on case objects, `assert_*` assertions) so that test
files migrate without rewriting.

Confirmed by the owner (2026-10-11) against the alternatives of busted or LuaUnit with a
Hecate plugin: one testing idiom consistent with the object model outweighs reusing an
existing runner.

## Consequences

- One testing idiom for the framework and its users.
- `test` must be built early and kept small at its core.

## Verification

Phase 3 exit: every package's tests run under `hecate test`; the bootstrap harness is
deleted.
