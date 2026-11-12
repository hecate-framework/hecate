<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Documentation: a how-to page "Before going to production" (`website/en/how-to/`), a checklist of what to verify before an application is deployed: log severity, no secrets in error messages (the logger redacts field names, not free text), what the default logger and the access log record (query strings), `logging.redact`, secrets declared in `secrets`, limits, development mode off. Written after the `kernel` item so that it names its real configuration keys.
- status: in-progress
- lock_until: 2026-11-12T14:15:00Z
- last_update: 2026-11-12T12:45:00Z

## Done

- Claimed the item (branch `claude/relay-before-production`).

## Next steps

1. Inventory the real configuration keys and behaviours (`packages/config`, `packages/kernel`, `packages/log`, `packages/http`): log severity, `logging.redact`, `secrets`, `errors.expose_details`, `requests.inputs`, `server.grace_timeout`, limits, access log fields, environment `production`.
2. Write `website/en/how-to/before-going-to-production.md` and link it from `website/en/how-to/index.md` and the site navigation.
3. French translation (`website/fr`) if the site has the French locale for how-to pages.
4. `CHANGELOG.md`, run the docs checks (`check-links`, `check-docs-examples`, `check-glossary`), markdownlint, typecheck.
5. Review (`docs-writer`, `dx-reviewer`, `security-reviewer`), CI green, tick the roadmap item, delete this file, mark ready.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
