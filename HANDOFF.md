<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `config`: layered configuration validated by schemas; write its specification section in `docs/architecture/`, including the logging keys (OQ-62) and the `limits.max_depth` key that lowers the nesting depth of `json` and `schema` together (OQ-92).
- status: in-progress
- lock_until: 2026-11-08T23:10:00Z
- last_update: 2026-11-08T21:40:00Z

## Done

- Claimed. Previous item `container` is complete in PR #152, awaiting owner review (not merged, independent of `config`: config depends only on core and schema).

## Next steps

1. Read ADRs, `docs/architecture/overview.md`, `logging.md`, `docs/glossary.md`, schema README, OQ-62 and OQ-92.
2. Write the specification section `docs/architecture/configuration.md` (layers, precedence, secrets, logging keys, `limits.max_depth`); record missing decisions as open questions (with mirror issues).
3. Tests first (layer precedence, error messages), then implementation in `packages/config/src`.
4. README, website reference, CHANGELOG, review with `/review-package`, tick roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test config
```
