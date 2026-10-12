<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `tools/run.lua` task runner and the Phase 0 tasks of the catalogue in automation.md
- status: waiting-owner
- lock_until: 2026-10-12T12:52:50Z
- last_update: 2026-10-12T12:52:50Z

## Done

- Done tasks: check-adr-index, check-links, check-changelog, check-boundaries, check-glossary, check-lua-constructs, affected, matrix, gen-catalogue, gen-dependency-graph, new-package, gen-llms-txt (root llms.txt only; website/public and llms-full.txt wait for the website) (plus earlier: format, lint, typecheck, test, check-versions, check-rockspecs, check-package-structure).

## Next steps

1. (check-* tasks all done)
2. (done)
3. All catalogue tasks are implemented. To finish: after PR #12 (ci.yml) is merged, merge main into this branch, confirm green on ubuntu/macos/windows, then delete this file, tick the roadmap line and mark the PR ready.
4. (hooks, workflow, settings, CLAUDE.md commands are separate roadmap items)

## Decisions taken (and where they are recorded)

- Worked on the session branch `claude/sweet-feynman-2vx1ft` (session rule) instead of `claude/relay-<slug>`.
- PR #12 (CI matrix) awaits owner review; this work is independent of it.

## Doubts and questions for the owner

- check-glossary uses a curated deny-list (tools/lib/glossary.lua) of never-acceptable terms; context-dependent glossary terms are left to the terminologist reviewer. Confirm or extend.

## Commands to re-run

```sh
lua tools/run.lua --list
lua tools/run.lua check-adr-index
```
