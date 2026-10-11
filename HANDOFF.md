<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Spike: confirm luv builds and passes its tests against Lua 5.5 on Linux, macOS, Windows (resolves OQ-1).
- status: waiting-ci
- lock_until: 2026-10-11T18:49:22Z
- last_update: 2026-10-11T17:19:22Z

## Done

- Claimed the item (draft PR #4).
- Linux: luv 1.53.0-0 builds vs Lua 5.5.1, 167/167 tests pass.
- Added .github/workflows/spike-oq1.yml and docs/spikes/OQ-1.md (Linux filled in).
- First CI run failed (workflow bugs, not luv): LUA_BUILD_AS_DLL on non-Windows broke the Lua build; Windows LUA_CPATH was an MSYS path. Fixed, re-running.

## Next steps

1. Read spike-oq1 CI results for macOS/Windows on PR #4; fix workflow or record luv failures.
2. Fill the table in docs/spikes/OQ-1.md, finalise recommendation.
3. Delete spike workflow + HANDOFF.md, tick roadmap item, mark PR ready, comment for owner.

## Decisions taken (and where they are recorded)

None.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
git clone --recursive https://github.com/luvit/luv spikes/OQ-1/luv
```
