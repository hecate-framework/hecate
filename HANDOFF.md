# Handoff

- roadmap_item: Workflow `ci.yml` (affected packages × three platforms) calling only `tools/` tasks.
- status: waiting-ci   (pushed fix for pre-existing tools test failures exposed by running `test tools`)
- lock_until: 2026-10-12T20:12:04Z
- last_update: 2026-10-12T18:42:04Z

## Done

- Added `plan` job running the `affected` task; per-platform job lints and tests only affected packages (plus `tools` tests).
- Roadmap ticked, changelog updated.

## Next steps

1. Confirm CI is green on the three platforms (fetch-depth, base ref on push events).
2. Delete HANDOFF.md, mark PR ready, ask owner for review.

## Decisions taken (and where they are recorded)

- Kept one job per platform (not per package) to avoid 84 bootstraps; per-package matrix deferred.

## Doubts and questions for the owner

- Per-package matrix wanted later? `matrix` task exists.

## Commands to re-run

```sh
lua tools/run.lua affected --base origin/main
```
