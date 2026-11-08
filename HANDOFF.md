<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `container`: IoC container, lifetimes, cycle detection at boot; write its specification section in `docs/architecture/` (OQ-62).
- status: in-progress
- lock_until: 2026-11-08T14:10:00Z
- last_update: 2026-11-08T12:42:00Z

## Done

- Claimed the item (branch `claude/relay-container`, from `main`). PR #54 (`schema`) is complete and waits for the owner.

## Next steps

1. Read ADR 0007, `packages/container/README.md`, `docs/architecture/overview.md`; write the specification section in `docs/architecture/` (OQ-62).
2. Tests first, then implement bindings, lifetimes, boot validation, overrides.
3. Docs, README, CHANGELOG, roadmap tick.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
