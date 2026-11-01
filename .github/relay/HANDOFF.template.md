<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: <exact text of the roadmap line>
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: YYYY-MM-DDTHH:MM:SSZ
- last_update: YYYY-MM-DDTHH:MM:SSZ

## Done

## Next steps

1.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
