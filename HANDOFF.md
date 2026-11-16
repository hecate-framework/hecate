<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc`: project documentation generator for user projects (OpenAPI reference, `hecate doc build`), with the Phase 1 gate deferrals (Windows-valid page ids, NFC/NFD), `---@meta` generation, and theme extension points (OQ-38)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-17T00:46:00Z
- last_update: 2026-11-16T23:17:00Z

## Done

## Next steps

1. Read docs/architecture/documentation.md §project sites, packages/doc/README.md; split the item into steps (Windows-safe page ids + NFC first, then project site build, OpenAPI reference, `---@meta`, theme extension points, docs/changelog).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
