<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`.
- status: in-progress
- lock_until: 2026-10-23T20:13:43Z
- last_update: 2026-10-23T18:43:43Z

## Done

- Step 1 (this run): `benchmarks/scenarios/tcp-echo/{server,load}.lua`, `benchmarks/run.lua` (runner, medians/spread), `benchmarks/lib/stats.lua` (percentile, median, Mann-Whitney U) with tests in `tools/tests/benchmark_stats_test.lua`. The load generator is written in Lua on our own reactor (open loop, latency from the due time, no third-party tool, so no dependency decision needed).
- Measured here (sandbox, not publishable): 200 connections at 5000-15000 req/s: p50 about 0.8 ms; 10 000 connections held with 0 errors at 5000 req/s but p50 about 25 ms and p99 about 245 ms (20000 req/s: seconds, saturated). Worth profiling later (timers per connection in the generator vs the server).
- Earlier: claimed. `doc` mobile menu is #30 (awaiting review), `log` is #29 (locked by another run until 23:10Z); next free item is the benchmarks harness.

## Next steps

1. `bench --compare` (A/B interleaved against a base checkout, Mann-Whitney p < 0.01 and > 10 %) using `stats.mann_whitney`; wire `benchmarks/run.lua` into the `bench` task (discover scenarios).
2. `.github/workflows/benchmarks.yml` (build base and head, A/B/A/B, >= 5 rounds).
3. Docs (benchmarks/README.md layout and usage, website if any), CHANGELOG `[Unreleased]`, tick the roadmap item, mark PR ready.

## Decisions taken (and where they are recorded)

- Branch is the session-designated `claude/sweet-feynman-83tsbj`, not `claude/relay-benchmarks`.

## Doubts and questions for the owner

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"
lua tools/run.lua test tools
lua benchmarks/run.lua tcp-echo --rounds=2 --connections=200 --rate=5000 --duration=2 --warmup=1 --lua=$(command -v lua)
```
