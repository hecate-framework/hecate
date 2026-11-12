# Phase 2 benchmarks: `plaintext`, `kernel-json` and the deferred performance findings

The roadmap item "Benchmarks: plaintext and JSON scenarios" (Phase 2) adds two network scenarios and judges, with a
measurement, the minor performance findings deferred to it: RE2, J4 and LO4 of the
[Phase 1 review](phase-1-review-package.md), the `router` findings of the 2026-11-02 review, and P5 and P6 of the
[`schema` review](schema-review-package.md). Each finding is kept or fixed; this page records the measurement behind
each verdict.

## Conditions

All figures come from one Claude Code cloud VM (Ubuntu 24.04, 4 vCPUs, shared and virtualised), measured on
2026-11-12 at the head of `claude/relay-benchmarks-plaintext-json`. They compare variants measured in the same session
and are **not quotable** as absolute numbers (benchmarks/README.md: absolute figures come from the owner's hardware).
The server was pinned to one CPU and the load generator to two others.

- Saturation of one server process (100 connections, offered 12 000 requests/s, 3 rounds of 4 s, median):
  `plaintext` about 9 700 requests/s, `kernel-json` about 8 300 requests/s. So one request costs about 100 µs in the
  HTTP stack and the reactor, and the kernel (routing, dispatch, filter chain, represent, JSON encoding) adds about
  15 %, some 17 µs. Below saturation (5 000 requests/s) the p50 latency of both is about 0.7 ms.
- Pipelining (`--pipeline=16`) does not raise the saturation point: the generator is not the bottleneck.
- A sampling profile (a count hook every 1 000 VM instructions, on every coroutine) puts about half of the Lua time of
  either server in `hecate.reactor` (timer heap, suspend and resume, scopes of `reactor.deadline`) and about 15 % in
  `hecate.http` (fields, response writing). Such a hook sees neither the C time (luv, system calls, the llhttp and JSON
  native modules) nor the garbage collector, and it overweights tight Lua loops: the two reactor experiments below
  confirm that what it showed did not translate into throughput.

## Verdicts

| Id | Finding | Measurement | Verdict |
|---|---|---|---|
| RE2 | three table allocations per suspend and resume (`reactor.lua`, `context.suspend`) | Experiment: `context.suspend` returns the resumed values through a helper instead of `table.pack`, and the scheduler step handles the common suspension without packing the result of `coroutine.resume` (two tables fewer per suspension). `bench plaintext --compare=HEAD`, 7 rounds at saturation: throughput -3.8 %, p = 0.32, no significant change; `reactor/scheduler`: fork and join about 215 000 → 175 000 coroutines/s (the extra `coroutine.status` call). | kept: no gain, the change was reverted |
| (new) | the timer heap takes about a quarter of the Lua samples of `plaintext`: the server sets a deadline per read and per write and cancels nearly all of them, and cancelled entries stay in the heap until a compaction | Experiment: an indexed heap where a cancelled timer leaves at once (O(log n)). `bench plaintext --compare=HEAD`, 7 rounds at saturation: throughput -1.5 %, p = 0.38, no significant change; `reactor/scheduler` concurrent timers unchanged (about 77 000 timers/s either way). | kept: no gain, the change was reverted |
| J4 | per-key allocation in the Rust encoder (`packages/json/native/src/lib.rs`) | `json.encode({ message = "Hello, World!" })`: about 2.0 µs per call, most of it a fixed per-call cost, not per key; that is about 2 % of a `kernel-json` request. `bench json/codec`: encode of records 40 MB/s against decode 150 MB/s (the float text noted in OQ-52 is the larger cost on numbers). | kept: under 2 % of a request; revisit with OQ-52 on dedicated hardware |
| LO4 | `Logger:with_context` rebuilds the severity list (`logger.lua`) | No package calls `with_context` on the request path (`grep` over `packages/*/src`); the scenarios log nothing per request. `bench log/logger`: an enabled call with a child context costs 2.1 µs against 2.0 µs without. | kept: not on the request path |
| router | at least four tables per match, a second walk on 404 and 405, the 9-argument recursive `tree.walk`, `rest_of` rescanning segments, the `%%(.?.?)` decode pattern | `packages/router/benchmarks/match.lua`: a static match costs 1.3 to 1.5 µs and a match with two parameters 2.4 to 2.9 µs, from 33 to 30 003 routes; that is 1 to 3 % of a request. The static rate falls by 5 to 12 % at 30 003 routes (708 000 to 761 000 → 670 000 matches/s), the cache effect already noted. 404 and 405 are not on the measured path. | kept: 1 to 3 % of a request |
| P5 | a class-bound build costs about 75 % more than a plain object build | Same two-field shape: plain build 1.26 µs, class-bound build 2.24 µs (+78 %), so about 1 µs per instance, under 1 % of a request; neither scenario builds a class instance. | kept; to look at again with the Phase 4 database scenarios, which build many instances per request |
| P6 | `format` validators cost 0.6 to 1.1 µs per call | `validate string-email`: about 1.1 µs per call (843 000 per second); a request validating a few formatted fields spends a few µs, a few % at most. | kept |

## Found on the way

- `packages/schema/benchmarks/validate.lua` stopped at its class-bound section: `schema.of` now requires a class to
  declare `schema.Representable` (checked by `finalise`), and the benchmark's classes did not. Fixed in this pull
  request; no test runs the micro-benchmarks, so the failure went unnoticed.
- The summary of `lua tools/run.lua bench` misreads two benchmark outputs: `log/logger` prints labels with a number in
  them (`enabled call, 3 fields 2023 ns/call`), which the summary splits at the number, and `router/match` prints a
  table, which yields no measurement line. The raw output keeps the right figures. Deferred: a tooling fix, recorded
  in the roadmap (Continuous).
- The `validation` and `routing` scenarios of the benchmarks/README.md table are not part of this item and stay to be
  written; the table says so.
