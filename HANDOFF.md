<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc`: project documentation generator for user projects (OpenAPI reference, `hecate doc build`), with the Phase 1 gate deferrals (Windows-valid page ids, NFC/NFD), `---@meta` generation, and theme extension points (OQ-38)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-16T23:33:35Z
- last_update: 2026-11-16T23:23:35Z

## Done

- Step 1: Windows-valid page ids refused with `BuildError`; page ids stored in NFC through an in-repo Latin table (OQ-140, issue #219).

## Next steps

1. Project site build (`hecate doc build` library side): API reference from OpenAPI, code reference from the project annotations, configuration reference, module/route map (docs/architecture/documentation.md, "Project documentation generated for users").
2. `---@meta` generation for LuaLS from the schemas of a project (OQ-96).
3. Theme extension points (OQ-38): site configuration `logo`, CSS custom-properties override file for colours; marks never recoloured.
4. Website reference, README, CHANGELOG, tick the roadmap item, delete this file.

## Decisions taken (and where they are recorded)

- NFC table limited to Latin: OQ-140 (conservative option (a)).

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
