<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up: specify then implement `offload` (Lua functions on the libuv thread pool), split from the Phase 1 item (OQ-27).
- status: in-progress
- lock_until: 2026-11-12T08:12:08Z
- last_update: 2026-11-12T06:42:08Z

## Done

- Claimed the item (this commit).

## Next steps

1. Specify `offload` in `docs/architecture/concurrency.md` (contract: what may be passed, results, errors, cancellation, pool size), basis luv `new_work`; record any undecided choice in `docs/open-questions.md` (and its mirror issue).
2. Tests first (`packages/reactor/tests`), then implement `reactor.offload`.
3. README, website reference/how-to, CHANGELOG, benchmark if relevant.
4. Reviews (pkg-reactor, api-reviewer, cross-platform-reviewer, test-engineer), CI green on three platforms, tick the roadmap item, delete this file.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test reactor
```
