<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: log the answers of the input step (owner remark on pull request #195, 2026-11-13).
- status: in-progress
- lock_until: 2026-11-14T10:58:32Z
- last_update: 2026-11-14T09:28:32Z

## Done

## Next steps

1. Read packages/kernel (input.lua, logging.lua, dispatcher.lua, problems.lua) and the guard's logging.
2. Write tests first, then log 400/415/422 of the input step.
3. Update website how-to, README, CHANGELOG, tick roadmap.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals
lua tools/run.lua typecheck
lua tools/run.lua test kernel
```
