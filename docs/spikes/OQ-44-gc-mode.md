# OQ-44: garbage collector mode for a coroutine-per-request server

Question (owner, 2026-10-18, after a third-party analysis proposing generational mode for
Hecate): which collector mode and tuning suit a process that serves many short-lived requests
next to a large long-lived heap (routes, compiled schemas, singletons)? This spike measures it on
Lua 5.5.1 and corrects the API vocabulary.

## Facts about Lua 5.5 (checked on the Lua 5.5.1 used by Hecate)

- The tuning calls are `collectgarbage("incremental", pause, stepmul, stepsize)` and
  `collectgarbage("generational", minor, major)`. **`setpause` and `setstepmul` do not exist in
  5.5** (they are rejected as invalid options), and `setminormul` and `setmajormul` never existed.
  Code or advice using them raises an error.
- The mode a state starts in depends on the host: the standalone `lua` switches to
  **generational** at startup (`lua.c`), while a state created by an embedding host
  (`luaL_newstate`, as the packaged CLI executable will do) starts **incremental**. Left alone,
  Hecate would run in a different mode depending on how it is launched, so the mode must be set
  explicitly at startup.
- Defaults: pause 200, stepmul 100, stepsize 13 (incremental); minor 20, major 100
  (generational).
- Lua 5.1 and LuaJIT also have incremental collectors, not stop-the-world ones. Lua 5.5 adds
  incremental major collections (ADR 0001 lists them), but the reason for the 5.5 target is the
  `global` declarations, not the collector.

## Measurement

[`OQ-44/churn.lua`](OQ-44/churn.lua) runs a coroutine per request, each allocating a request
table with headers, a decoded tree and coercion results across three yields, with 500 requests in
flight, on top of a long-lived heap of N routes. It reports throughput, the latency of each
resume step (p50, p99, p99.9, maximum) and the peak memory. Cloud session, one run per cell:
indicative, not a benchmark (the harness is a Phase 1 item).

Large long-lived heap (400 000 objects, about 150 MB live, 150 000 requests):

| Mode | req/s | step p99 | step p99.9 | worst step | peak |
|---|---|---|---|---|---|
| incremental default (200, 100) | 6980 | 261 µs | 649 µs | 306 ms | 388 MB |
| incremental pause 150 | 7210 | 283 µs | 751 µs | 406 ms | 390 MB |
| incremental pause 150, stepmul 400 | 7260 | 268 µs | 734 µs | 304 ms | 388 MB |
| generational default (20, 100) | 8760 | 109 µs | 250 µs | 242 ms | 357 MB |
| generational minor 50 | 7980 | 145 µs | 580 µs | 225 ms | 357 MB |
| generational major 300 | 8820 | 114 µs | 340 µs | 278 ms | 357 MB |

Small long-lived heap (40 000 objects, 100 000 requests):

| Mode | req/s | step p99 | worst step | steps over 5 ms |
|---|---|---|---|---|
| incremental default | 10470 | 224 µs | 34 ms | 55 |
| incremental, small steps (stepsize 10) | 9380 | 265 µs | 42 ms | 54 |
| generational default | 7370 | 78 µs | 75 ms | 248 |

## Findings

1. **Generational mode is not a universal win.** With a large long-lived heap it gave about 25%
   more throughput and a p99 about 2.4 times lower. With a small one it gave a better p99 but
   about 30% less throughput and more slow steps. The direction of the third-party analysis
   (generational suits request churn over a big old heap) holds in one regime and reverses in
   the other, so the choice has to be measured on real request shapes.
2. **Neither mode bounds the worst pause.** Occasional steps of tens to hundreds of milliseconds
   occur in both, and the worst step grows with the long-lived heap (about 34 ms with 40 000
   objects, 300 ms with 400 000), whatever the step size or multipliers. Tuning moves the tail
   (p99) but not the maximum.
3. **Two consequences for the design.** Keep the heap of each process small, which the
   multi-process design helps with (ADR 0023: N workers each hold their own copy, so a large
   shared structure costs N times the memory, which argues for compact long-lived data), and avoid
   one gigantic table, which is traversed in one step. In generational mode, requests that stay in
   flight across many minor collections become old and are only reclaimed by a major one: the
   long-latency requests are the ones that inflate memory.
4. The default of Lua is not Hecate's decision: set the mode explicitly at boot.

## Recommendation

Set the mode explicitly in the worker start-up (`runtime.gc` in the configuration, with the
mode, and the multipliers for the chosen mode). Until the benchmark harness provides real request
shapes, start with `generational` for workers, because the regime that matters for a framework
server (a large old heap of routes, schemas and singletons) is the one where it wins, and record
the small-heap regression. Revisit when `benchmarks/` has the plaintext and JSON scenarios (Phase
2 item). Decision for the owner: OQ-44.
