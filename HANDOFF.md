<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **First item of Phase 3 (owner decision of 2026-11-13): a readable writing style.** Write a "Writing style" section in `docs/architecture/documentation.md`, after the manner of *Programming in Lua* (Ierusalimschy) [...] Pilot it on the 8 pages written at the Phase 2 gate [...] and submit them to the owner before any other Phase 3 item starts.
- status: in-progress
- lock_until: 2026-11-14T00:03:42Z
- last_update: 2026-11-13T22:33:42Z

## Done

1. Claimed the item (this note, draft pull request).

## Next steps

1. Write the "Writing style" section in `docs/architecture/documentation.md` (and a pointer in `website/CLAUDE.md`
   and `.claude/agents/docs-writer.md`).
2. Pilot it on the how-tos: `how-to/map-domain-errors-to-problem-details.md`, `how-to/filters.md`,
   `how-to/concurrency.md`, `how-to/multi-process-deployment.md`.
3. Pilot it on `reference/schema-keywords-and-formats.md` and the explanations `explanation/architecture-and-layers.md`,
   `explanation/object-model.md`, `explanation/concurrency-model.md`.
4. Run the docs gates (`check-docs-examples`, `check-examples`, `check-links`, `check-glossary`), CHANGELOG, then mark
   the pull request ready and ask the owner to review the style and the 8 pages. The item is ticked only after the
   owner approves (status `waiting-owner`).

## Decisions taken (and where they are recorded)

- Work happens on the session branch `claude/sweet-feynman-6v4js8` (the session forbids pushing to another branch),
  not on `claude/relay-writing-style`.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua check-docs-examples
lua tools/run.lua check-links
lua tools/run.lua check-glossary
```
