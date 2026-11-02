<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `schema`: refinement types, composition, coercion, validation with JSON Pointer error paths, JSON Schema 2020-12 emission.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-02T15:28:10Z
- last_update: 2026-11-02T13:58:10Z

## Done

## Next steps

1. Read docs/architecture/schemas-and-contracts.md, ADRs, OQ-50; plan steps (types, validation, coercion, JSON Schema emission, instances + sent set).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
