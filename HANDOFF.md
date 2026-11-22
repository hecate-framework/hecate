<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T11:18:30Z
- last_update: 2026-11-22T09:48:30Z

## Done

- Claimed the item (branch `claude/loving-shannon-flx2ar`, draft pull request #231).
- Step 1: parser, dispatcher (`hecate.cli.run`), `--help`, `--json`, exit codes, `version`; tests in `packages/cli/tests/unit`; typecheck, lint and gates green locally.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029 and the OQ-13 spike (not yet read in full).
2. `bin/hecate.lua` entry point wiring `cli.run` with the real runtime (versions, platform) and `hecate.json` for `--json`; `--version` alias.
3. Manifest `hecate.project.lua`: sandboxed evaluation with an instruction limit, validation with `hecate.schema` (including the `doc` section).
3b. Owner request (2026-11-22): shell completion, `hecate completion <shell>` plus hidden `__complete`, driven by the command declarations (roadmap `cli` item). Cheap and pure Lua: do it right after the entry point.
4. Then, one step each: lockfile, LuaRocks orchestration, `new` and templates, `install/add/remove/update`, `serve`, `test`, `doc`, `contract`, `doctor`, `toolchain`; the native executable (OQ-13, ADR 0029) in its own steps.
5. Package README, CHANGELOG, roadmap sub-items as steps land.

## Decisions taken (and where they are recorded)

none yet

## Doubts and questions for the owner

none yet

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
