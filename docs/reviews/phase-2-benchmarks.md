# Phase 2 benchmarks: `plaintext`, `kernel-json` and the deferred performance findings

The roadmap item "Benchmarks: plaintext and JSON scenarios" (Phase 2) adds two network scenarios and judges, with a
measurement, the minor performance findings deferred to it: RE2, J4 and LO4 of the
[Phase 1 review](phase-1-review-package.md), the `router` findings of the 2026-11-02 review, and P5 and P6 of the
[`schema` review](schema-review-package.md). Each finding is kept or fixed; this page records the measurement behind
each verdict. A performance-engineer and a test-engineer reviewed the first version of this page and of the load
generator; their points are taken into account below (the generator under-counted the throughput at saturation, and
some verdicts claimed more than their measurement showed).

## Conditions

All figures come from one Claude Code cloud VM (Ubuntu 24.04, 4 vCPUs, shared and virtualised), measured on
2026-11-12 at the head of `claude/relay-benchmarks-plaintext-json`. They compare variants measured in the same session
and are **not quotable** as absolute numbers (benchmarks/README.md: absolute figures come from the owner's hardware).
The server was pinned to one CPU and the load generator to two others.

- Saturation of one server process (100 connections, offered 12 000 requests/s, 3 rounds of 4 s, median and
  max/min spread): `plaintext` about 10 750 requests/s (spread 1.15), `kernel-json` about 9 500 requests/s (spread
  1.03). So one request costs about 93 µs in the HTTP stack and the reactor, and the kernel (routing, dispatch, filter
  chain, represent, JSON encoding) adds about 12 µs, some 13 %: an order of magnitude, from two separate runs. Below
  saturation (5 000 requests/s) the p50 latency of both is about 0.7 ms.
- The server, not the generator, is the bottleneck: during a 7 s saturated `plaintext` run the server process used
  6.45 s of CPU (its whole core) and the generator 2.5 s over its two cores.
- A sampling profile (a count hook every 1 000 VM instructions, on every coroutine) puts about half of the Lua time of
  either server in `hecate.reactor` (timer heap, suspend and resume, scopes of `reactor.deadline`) and about 15 % in
  `hecate.http` (fields, response writing). Such a hook sees neither the C time (luv, system calls, the llhttp and JSON
  native modules) nor the garbage collector, and it overweights tight Lua loops: the two reactor experiments below
  confirm that what it showed did not translate into throughput.

## Verdicts

| Id | Finding | Measurement | Verdict |
|---|---|---|---|
| RE2 | three table allocations per suspend and resume (`reactor.lua`, `context.suspend`) | Experiment: `context.suspend` returns the resumed values through a helper instead of `table.pack`, and the scheduler step handles the common suspension without packing the result of `coroutine.resume` (two tables fewer per suspension). `bench plaintext --compare=HEAD`, 7 rounds at saturation: throughput -3.8 %, p = 0.32, no significant change; `reactor/scheduler`: fork and join about 215 000 → 175 000 coroutines/s (the extra `coroutine.status` call). | kept: no gain detectable at the 10 % threshold on this VM, the change was reverted. The variant also added a `coroutine.status` call, so it is not a pure test of the allocations; a cleaner variant is worth trying only on dedicated hardware |
| (new) | the timer heap takes about a quarter of the Lua samples of `plaintext`: the server sets a deadline per read and per write and cancels nearly all of them, and cancelled entries stay in the heap until a compaction | Experiment: an indexed heap where a cancelled timer leaves at once (O(log n)). `bench plaintext --compare=HEAD`, 7 rounds at saturation: throughput -1.5 %, p = 0.38, no significant change; `reactor/scheduler` concurrent timers unchanged (about 77 000 timers/s either way). | kept: no gain detectable at the 10 % threshold on this VM, the change was reverted |
| J4 | per-key allocation in the Rust encoder (`packages/json/native/src/lib.rs`) | `json.encode` of an object of short string members: 1 key 1.9 µs, 5 keys 3.2 µs, 20 keys 7.5 µs, 50 keys 15.4 µs, so a fixed cost of about 1.7 µs per call plus about 275 ns per key; the `kernel-json` document is about 2 % of a request, and a 20-key document would be about 7 %. `bench json/codec`: encode of records 40 MB/s against decode 150 MB/s (the float text noted in OQ-52 is the larger cost on numbers). | kept: a few % of a request for common documents; revisit the per-key cost with OQ-52 on dedicated hardware |
| LO4 | `Logger:with_context` rebuilds the severity list (`logger.lua`) | No package calls `with_context` on the request path (`grep` over `packages/*/src`), but an application may call it per request. `with_context` itself cost 1.86 µs, of which the round trip of the severity through `Logger:severity()` (which copies the list of severities) and its resolution again in the constructor. Copying the ordinal into the child: 1.31 µs (-29 %), with a test that a child keeps the severity of its parent. | fixed in this pull request |
| router | at least four tables per match, a second walk on 404 and 405, the 9-argument recursive `tree.walk`, `rest_of` rescanning segments, the `%%(.?.?)` decode pattern | `packages/router/benchmarks/match.lua`, which now also measures a 405 and a wide fan-out under the matched prefix, as the roadmap asked: from 33 to 30 003 routes, a static match costs 1.3 to 1.5 µs, two parameters 2.4 to 2.6 µs, a miss (404) 1.7 to 1.9 µs and a 405 (second walk and `Allow` list) 2.5 to 2.7 µs: 1 to 3 % of a request. Under a prefix with 12 to 10 002 static siblings, the static and parameter matches do not slow down (585 000 to 637 000 and 517 000 to 568 000 per second). At 30 003 routes every column, the miss included, falls by 6 to 11 % against 3 003: the fan-out case rules out a walk that grows with the siblings, which leaves memory effects of a large tree (not checked further). | kept: 1 to 3 % of a request; caching the `Allow` lists would save part of 2.6 µs on a 405 only |
| P5 | a class-bound build costs about 75 % more than a plain object build | Same two-field shape: plain build 1.26 µs, class-bound build 2.24 µs (+78 %), so about 1 µs per instance, under 1 % of a request; neither scenario builds a class instance. | kept; to look at again with the Phase 4 database scenarios, which build many instances per request |
| P6 | `format` validators cost 0.6 to 1.1 µs per call | `validate string-email`: about 1.1 µs per call (843 000 per second); a request validating a few formatted fields spends a few µs, a few % at most. Only the email format was timed, and the `validation` scenario of the README, the realistic mix the roadmap asked for, is not written yet. | kept, provisionally: to judge again with the `validation` scenario |

## Found on the way

- `packages/schema/benchmarks/validate.lua` stopped at its class-bound section: `schema.of` now requires a class to
  declare `schema.Representable` (checked by `finalise`), and the benchmark's classes did not. Fixed in this pull
  request; no test runs the micro-benchmarks, so the failure went unnoticed.
- The summary of `lua tools/run.lua bench` misreads two benchmark outputs: `log/logger` prints labels with a number in
  them (`enabled call, 3 fields 2023 ns/call`), which the summary splits at the number, and `router/match` prints a
  table, which yields no measurement line. The raw output keeps the right figures. Deferred: a tooling fix, recorded
  in the roadmap (Continuous).
- The `validation` and `routing` scenarios of the benchmarks/README.md table are not part of this item and stay to be
  written; the table says so, and the roadmap (Continuous) carries them with P6.
- The A/B comparison runs the base tree with the native modules built from the head (the base worktree has none of its
  own): a pull request that changes the native code of `json` or `http` is compared head against head on that code.
  benchmarks/README.md says so.
