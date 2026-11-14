<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Spike OQ-17 (split tool for the read-only mirrors: `splitsh-lite`, `git subtree split`, `git filter-repo`; determinism and speed), report to the owner before the mirrors item (owner decision of 2026-11-13).
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T17:11:11Z
- last_update: 2026-11-14T15:41:11Z

## Done

## Next steps

1. Clone the three tools under spikes/OQ-17/ and measure determinism and speed on a synthetic monorepo history.
2. Write docs/spikes/oq-17-split-tool.md, update OQ-17 and the roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
