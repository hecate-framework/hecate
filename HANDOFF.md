<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: log the answers of the input step (owner remark on pull request #195, 2026-11-13).
- status: in-progress
- lock_until: 2026-11-14T11:11:13Z
- last_update: 2026-11-14T09:28:32Z

## Done

- Input step logs 400/415/422 at warning (input.lua, dispatcher passes logger), tests, website how-to, README, CHANGELOG, roadmap ticked.

## Next steps

1. Wait for CI on the three platforms; when green delete HANDOFF.md, mark PR ready, ask owner review.

## Decisions taken (and where they are recorded)

- Severity `warning`, in line with the guard; fields method, path, status, reason, codes (README, how-to).

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals
lua tools/run.lua typecheck
lua tools/run.lua test kernel
```
