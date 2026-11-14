<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: log the answers of the input step (owner remark on pull request #195, 2026-11-13)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T11:11:16Z
- last_update: 2026-11-14T09:41:16Z

## Done

## Next steps

1. Tests first in packages/kernel/tests/unit/input_test.lua, then log in input.compile (problems.lua guard logs 4xx at warning).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
