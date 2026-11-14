<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor.random(n)`, cryptographically secure bytes over libuv `uv_random`, used by the multipart boundaries of `http` (no `math.random` fallback), before `0.1.0` (OQ-73, owner decision of 2026-11-13).
- status: waiting-ci          <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T21:05:00Z
- last_update: 2026-11-14T19:50:00Z

## Done

- `reactor.random(n)` with unit tests (`system_test.lua`), `http` multipart boundaries use it, README, CHANGELOG, roadmap ticked, OQ-73 moved to Resolved. typecheck and doc gates pass locally. Tests could not run locally (no luv): CI decides.

## Next steps

1. Read CI on the three platforms; fix failures. Then delete HANDOFF.md, mark ready, ask the owner for review.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
