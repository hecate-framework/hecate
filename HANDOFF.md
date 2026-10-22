<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Benchmarks harness and first scenario (TCP echo); `benchmarks.yml`.
- status: in-progress
- lock_until: 2026-10-22T23:15:00Z
- last_update: 2026-10-22T21:45:00Z

## Done

- Claimed. `doc` mobile menu is #30 (awaiting review), `log` is #29 (locked by another run until 23:10Z); next free item is the benchmarks harness.

## Next steps

1. `benchmarks/scenarios/tcp-echo/` server (reactor + net) and a load profile.
2. `benchmarks/run.lua` runner; load generator choice (wrk2/oha are third-party tools: record in open-questions if a dependency decision is needed).
3. `bench --compare` and `benchmarks.yml` (A/B interleaved, Mann-Whitney U).
4. Docs, CHANGELOG, tick the roadmap item.

## Decisions taken (and where they are recorded)

- Branch is the session-designated `claude/sweet-feynman-83tsbj`, not `claude/relay-benchmarks`.

## Doubts and questions for the owner

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"
lua tools/run.lua test tools
```
