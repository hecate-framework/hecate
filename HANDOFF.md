<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor.random(n)`, cryptographically secure bytes over libuv `uv_random`, used by the multipart boundaries of `http` (no `math.random` fallback), before `0.1.0` (OQ-73, owner decision of 2026-11-13).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T21:05:00Z
- last_update: 2026-11-14T19:35:00Z

## Done

## Next steps

1. Test first (`system_test.lua`), then `reactor.random` in `system.lua`, export in `init.lua`.
2. `http` multipart boundary uses it; README, CHANGELOG, website reference, tick roadmap and OQ-73 row.
3. typecheck, push, CI green on three platforms, delete HANDOFF.md, mark ready.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
