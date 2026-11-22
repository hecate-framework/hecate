<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T15:45:46Z
- last_update: 2026-11-22T14:15:46Z

## Done

- Claimed the item (branch `claude/loving-shannon-flx2ar`, draft pull request #231).
- Step 1: parser, dispatcher (`hecate.cli.run`), `--help`, `--json`, exit codes, `version`; tests in `packages/cli/tests/unit`; typecheck, lint and gates green locally.
- Step 2: `packages/cli/bin/hecate.lua` entry point; shell completion (`completion <shell>`, hidden `__complete -- words`, `Command.hidden`); bash script checked by simulating `COMP_WORDS`. CI fix: `gen-catalogue` must be run after a README status change.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029 and the OQ-13 spike (not yet read in full).
2. Verify the zsh, fish and PowerShell completion scripts on a real shell (PowerShell may drop the empty last word: the script appends `""`, check on CI; add a CI step or a test that runs them where the shell exists). `--version` alias.
3. Manifest `hecate.project.lua`: sandboxed evaluation with an instruction limit, validation with `hecate.schema` (including the `doc` section).
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
