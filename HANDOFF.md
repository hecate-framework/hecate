<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `json`: codec (after OQ-5).
- status: in-progress
- lock_until: 2026-10-19T11:11:12Z
- last_update: 2026-10-19T09:41:12Z

## Done

- Claimed. Website item is already in open PR #24 (not a relay PR, awaiting owner); skipped.

## Next steps

1. Read ADR 0020, ADR 0021, schemas-and-contracts.md and packages/json/CLAUDE.md; plan steps.
2. Write tests first (pure-Lua value model: null/array markers, errors), then the native layer.

## Decisions taken (and where they are recorded)

- Work happens on the session-designated branch `claude/sweet-feynman-1zqg2u` instead of `claude/relay-json` (environment rule: never push to another branch).

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua test json
```
