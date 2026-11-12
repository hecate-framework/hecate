<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Documentation: a how-to page "Before going to production" (`website/en/how-to/`), a checklist of what to verify before an application is deployed: log severity, no secrets in error messages (the logger redacts field names, not free text), what the default logger and the access log record (query strings), `logging.redact`, secrets declared in `secrets`, limits, development mode off. Written after the `kernel` item so that it names its real configuration keys.
- status: in-progress
- lock_until: 2026-11-12T14:45:00Z
- last_update: 2026-11-12T13:15:00Z

## Done

- Claimed the item (branch `claude/relay-before-production`, draft pull request #179).
- Inventory of the real keys and behaviours, then the page `website/en/how-to/before-going-to-production.md`, linked from
  `how-to/index.md` and `OUTLINE.md`; `CHANGELOG.md` (b620e23). `check-links`, `check-docs-examples`, `check-changelog`,
  `gen-llms-txt` (no change: it lists packages only) and `typecheck` pass.

## Next steps

1. Review of the page (`dx-reviewer`, `security-reviewer`) against the code; fix what they find.
2. CI green (markdownlint, links), tick the roadmap item, delete this file, mark the pull request ready, ask the owner.

## Decisions taken (and where they are recorded)

- No French translation in this pull request: `website/fr/how-to` does not mirror every English page yet (for example
  `configure-an-application.md` is English only); `translator-fr` can add it later.
- The page states that hecate writes no access log of its own (true of `kernel` and `http`: only the `on_response` hook).

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
