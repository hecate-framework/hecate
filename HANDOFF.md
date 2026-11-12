<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks: plaintext and JSON scenarios. (Phase 2, with the deferred performance findings RE2, J4, LO4, the router findings and the schema findings P5, P6)
- status: in-progress
- lock_until: 2026-11-12T11:11:45Z
- last_update: 2026-11-12T09:41:45Z

## Done

## Next steps

1. Read the benchmark harness (`benchmarks/run.lua`, `lib/runner.lua`, `scenarios/tcp-echo`), the `http` and `kernel` READMEs, and `docs/architecture/automation.md` (bench task).
2. Scenario `plaintext`: `benchmarks/scenarios/plaintext/{server,load}.lua` (`http.Server`, keep-alive, pipelining), an HTTP load generator on the reactor (open loop, latency from the due time), a smoke test in `tools` tests.
3. Scenario `json`: `benchmarks/scenarios/json/{server,load}.lua` (kernel application, one route, JSON encoding).
4. Wire both into `benchmarks.yml` and the `bench` task where `tcp-echo` is wired; README table and usage.
5. Judge the deferred findings with measurements (RE2, J4, LO4; router; schema P5, P6): keep or fix each, note the result in the reviews.
6. CHANGELOG, roadmap tick, CI green on three platforms.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
