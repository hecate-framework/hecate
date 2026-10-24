<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up: scope-local context, `reactor.with_local(key, value, fn)` and `reactor.local(key)` (ADR 0025, OQ-55)
- status: in-progress
- lock_until: 2026-10-24T23:11:15Z
- last_update: 2026-10-24T21:41:15Z

## Done

- Claimed the item. #34 (CI workflows) is locked by another run; #31 waits on the owner.

## Next steps

1. Specify in `docs/architecture/concurrency.md`.
2. Tests first, then implement in `packages/reactor`.
3. `log` default context provider + test; docs, README, changelog; tick roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua test reactor
```
