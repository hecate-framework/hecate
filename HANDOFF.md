<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor`: reactor over luv, scheduler, futures, `fork`/`join`/`select`, deadlines, scopes and cancellation, channels, semaphores, mutexes, monitors, timers, thread-pool offloading, signals
- status: in-progress
- lock_until: 2026-10-12T22:43:29Z
- last_update: 2026-10-12T21:13:29Z

## Done

- Claimed the item (previous item `core` merged in #17).

## Next steps

1. Install luv (system-Lua mode, >= 1.53.0-0) under `spikes/` or via luarocks tree; confirm `require "luv"` works.
2. Read concurrency.md, reactor README/CLAUDE.md, ADRs; write tests first for scheduler + futures.
3. Implement in steps: scheduler/futures, scopes/cancellation, sync primitives, timers, offload, signals.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- `luv` is not installed in the cloud image; may need network access to fetch it.

## Commands to re-run

```sh
lua tools/run.lua test reactor
```
