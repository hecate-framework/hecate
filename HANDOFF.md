<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Git hooks (`tools/hooks`).
- status: waiting-ci
- lock_until: 2026-10-12T20:04:29Z
- last_update: 2026-10-12T18:34:29Z

## Done

Implementation, tests, changelog, roadmap tick pushed. Local typecheck impossible (no LuaLS).

## Next steps

1. Wait for ci.yml on PR #14 to be green on the three platforms.
2. Then delete HANDOFF.md, mark PR ready, comment asking owner review.

## Decisions taken (and where they are recorded)

None beyond the spec (automation.md catalogue).

## Doubts and questions for the owner

tools tests: BoundariesTest.test_rockspec_deps and ConstructsTest.test_collectgarbage_param fail locally on main too.

## Commands to re-run

```sh
lua tools/run.lua test tools
```
