<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T11:28:29Z
- last_update: 2026-11-14T09:58:29Z

## Done

## Next steps

1. Read `docs/architecture/schemas-and-contracts.md`, `packages/openapi/CLAUDE.md`, ADR 0006; plan the steps (assembly first, tests first).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
