<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `container`: IoC container, lifetimes, cycle detection at boot; write its specification section in `docs/architecture/` (OQ-62).
- status: in-progress
- lock_until: 2026-11-08T14:45:00Z
- last_update: 2026-11-08T13:10:00Z

## Done

- Claimed the item (branch `claude/relay-container`, from `main`). PR #54 (`schema`) is complete and waits for the owner.
- Step 1: specification section `docs/architecture/container.md`, README/CHANGELOG/open-questions updated.

## Next steps

0. Deferred to a follow-up (conflicts with PR #54 on `DEFAULT_PACKAGES`/website.yml): register `container` in the reference site, add glossary terms (service scope, binding, lifetime).

1. DONE: specification written (`docs/architecture/container.md`, OQ-85 to OQ-89 open). Next: step 2 below.
2. Tests first, then implement bindings, lifetimes, boot validation, overrides.
3. Docs, README, CHANGELOG, roadmap tick.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
