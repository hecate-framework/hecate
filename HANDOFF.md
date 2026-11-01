<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `router`: radix tree, URI template subset, 404/405, reverse routing (+ percent-decode segments, dot segments; OQ-75)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-11-01T23:22:06Z
- last_update: 2026-11-01T21:52:06Z

## Done

## Next steps

1. Read docs/architecture/http-and-routing.md, ADR 0006, packages/router/CLAUDE.md; plan steps; tests first.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
