# OQ-44: garbage collector mode for a coroutine-per-request server

Question (owner, 2026-10-18, after a third-party analysis proposing generational mode for
Hecate): which collector mode and tuning suit a process that serves many short-lived requests
next to a large long-lived heap (routes, compiled schemas, singletons)? The owner's reason for
generational mode is to limit the cost of the ORM's mapping and change tracking on the rest of
the request. This spike measures it on Lua 5.5.1, with a generic workload and an ORM-shaped one,
and corrects the API vocabulary.

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

## ORM-shaped workload

The first workload above is generic and does not model the ORM, which the owner pointed out.
`churn.lua ... orm` adds one that does: each request builds a unit of work with an identity map,
about 420 entities (orders, customers, items), each with a field table and a snapshot of its
loaded state for change tracking, associations with back references (cycles), a lazy load across a
yield, a business step that modifies one entity in ten, a flush that diffs every tracked entity
against its snapshot and builds change sets, and a response tree: about 3000 tables per request,
200 requests in flight, 8000 requests, one run per cell (indicative).

| Long-lived heap | Mode | req/s | step p99 | step p99.9 | steps over 5 ms | worst step | peak |
|---|---|---|---|---|---|---|---|
| 40 000 objects | incremental default | 350 | 9.7 ms | 24.9 ms | 567 | 106 ms | 141 MB |
| 40 000 objects | incremental pause 150, stepmul 400 | 432 | 6.7 ms | 17.3 ms | 450 | 58 ms | 205 MB |
| 40 000 objects | generational default | 356 | 4.2 ms | 54.7 ms | 252 | 242 ms | 141 MB |
| 40 000 objects | generational minor 50 | 353 | 4.0 ms | 40.8 ms | 225 | 264 ms | 141 MB |
| 40 000 objects | generational major 300 | 356 | 4.1 ms | 46.7 ms | 238 | 282 ms | 141 MB |
| 400 000 objects | incremental default | 388 | 8.2 ms | 22.1 ms | 446 | 109 ms | 460 MB |
| 400 000 objects | incremental pause 150, stepmul 400 | 366 | 9.5 ms | 26.6 ms | 448 | 94 ms | 460 MB |
| 400 000 objects | generational default | 350 | 2.8 ms | 87.0 ms | 123 | 600 ms | 479 MB |
| 400 000 objects | generational minor 50 | 357 | 2.7 ms | 89.2 ms | 102 | 793 ms | 479 MB |
| 400 000 objects | generational major 300 | 352 | 2.8 ms | 91.5 ms | 111 | 626 ms | 479 MB |

For the ORM-shaped load:

- Throughput does not change with the mode.
- Generational mode does what the owner expects for the typical slow step: the p99 is 2 to 3
  times lower (4.2 against 9.7 ms, 2.8 against 8.2 ms) and slow steps (over 5 ms) are 2 to 4 times
  rarer, because the many young entities, snapshots and change sets of a finished request are
  reclaimed by cheap minor collections and the long-lived data is no longer re-traversed.
- It has a cost the generic workload hid: its rare major collections stop the whole process for a
  long time, 240 to 280 ms with a small long-lived heap and 600 to 800 ms with a large one,
  against about 100 ms for incremental. The p99.9 is worse as well (40 to 90 ms against 17 to 27 ms).
  The minor and major multipliers do not remove it.
- Peak memory is the same.

## Findings (generic workload)

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

## Decision and what to measure next

Owner decision (2026-10-18): generational mode to start with, configured from `runtime.gc`, and
revisited once the benchmark harness exists. The ORM measurement supports the reason (the typical
request is faster to collect) and adds one thing to watch: the long stop of a major collection.

For the harness (`benchmarks/`, with real request shapes):

- an ORM scenario like the one above, with the unit of work held across database waits;
- the stall of a major collection per worker, which hits only the connections of that worker (with
  N workers, about 1/N of the traffic, ADR 0023), and how it grows with the long-lived heap;
- mitigations to compare: a larger `major` multiplier, a full collection scheduled when a worker
  is idle, recycling a worker after a number of requests (a rolling restart, ADR 0023), and a
  smaller long-lived heap per worker.
