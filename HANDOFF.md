<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc`: project documentation generator for user projects (OpenAPI reference, `hecate doc build`), with the Phase 1 gate deferrals (Windows-valid page ids, NFC/NFD), `---@meta` generation, and theme extension points (OQ-38)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-17T11:30:00Z
- last_update: 2026-11-17T10:00:00Z

## Done

- Step 1: Windows-valid page ids refused with `BuildError`; page ids stored in NFC through an in-repo Latin table (OQ-140, issue #219).

- Step 2: `hecate.doc.project` (API reference + route map from an OpenAPI document, configuration reference from a JSON Schema, `project.build`), tests in `tests/unit/project_test.lua`.

- Step 3: project code reference: `project.build{ code = { root, name } }` runs `reference_site` on `<root>/src` (new `layout` option); OQ-141 was already recorded (issue #220).

- Step 4: `project.meta(schemas, namespace)` generates `---@meta` files from named schemas (OQ-96); `gen-meta` CLI wiring stays with `cli` (OQ-121).

- Step 5: theme extension points (OQ-38): `logo` and `colors` site options, tests in `config_test.lua` and `site_test.lua`.

## Next steps

1. Website reference, README, CHANGELOG, tick the roadmap item, delete this file.

## Decisions taken (and where they are recorded)

- NFC table limited to Latin: OQ-140 (conservative option (a)).

## Doubts and questions for the owner

## Commands to re-run

```sh
eval "$(luarocks path)"        # luv is found only after this
lua tools/run.lua build-native doc   # and json, before tests
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
