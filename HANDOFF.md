<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `tools/run.lua` task runner and the Phase 0 tasks of the catalogue in automation.md
- status: in-progress
- lock_until: 2026-10-12T14:19:19Z
- last_update: 2026-10-12T12:49:19Z

## Done

- Done tasks: check-adr-index, check-links, check-changelog, check-boundaries (plus earlier: format, lint, typecheck, test, check-versions, check-rockspecs, check-package-structure).

## Next steps

1. check-lua-constructs, check-glossary
2. affected, matrix
3. new-package, gen-catalogue, gen-dependency-graph, gen-llms-txt
4. (hooks, workflow, settings, CLAUDE.md commands are separate roadmap items)

## Decisions taken (and where they are recorded)

- Worked on the session branch `claude/sweet-feynman-2vx1ft` (session rule) instead of `claude/relay-<slug>`.
- PR #12 (CI matrix) awaits owner review; this work is independent of it.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua --list
lua tools/run.lua check-adr-index
```
