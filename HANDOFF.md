<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Spike OQ-13 (standalone CLI executable: Lua 5.5, the CLI modules and the native modules in one binary per platform; code signing on macOS and Windows), time-boxed, report and recommendation to the owner before the `cli` v1 item (owner decision of 2026-11-13).
- status: in-progress
- lock_until: 2026-11-14T14:34:44Z
- last_update: 2026-11-14T13:04:44Z

## Done

- Claimed (openapi item is held by another run on #198; `test` depends on `openapi`).

## Next steps

1. Read ADR 0010, OQ-13 in `docs/open-questions.md`, `packages/cli/README.md`; look at `docs/spikes/OQ-4-tls.md` for the report format.
2. Experiments under `spikes/OQ-13/` (git-ignored): embed Lua 5.5 + a Lua module + a C module in one binary on Linux.
3. Write `docs/spikes/OQ-13-standalone-executable.md` (report, options, recommendation; never decide).
4. Update OQ-13 row, roadmap tick, CHANGELOG if needed; mark ready, ask for owner review.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals
lua tools/run.lua typecheck
```
