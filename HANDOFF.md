<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `cli` v1: self-contained executable, `new`, `install`, `add`, `remove`, `update`, `serve [--watch]`, `test`, `doc`, `contract`, `toolchain`, `doctor`, `version` (docs/roadmap.md, Phase 3). Started on the owner's request of 2026-11-22.
- status: in-progress
- lock_until: 2026-11-22T11:08:06Z
- last_update: 2026-11-22T09:38:06Z

## Done

- Claimed the item (branch `claude/loving-shannon-flx2ar`, handoff, draft pull request). No code yet.

## Next steps

1. Read ADR 0009, 0010, 0028, 0029, `docs/architecture/cli-and-packaging.md`, `docs/spikes/OQ-13-standalone-executable.md`, `packages/cli/CLAUDE.md`, and the Lua-side layout of `packages/doc` (entry points under `bin/`).
2. Pure-Lua foundation first (tests first): command dispatcher, argument parser, `--help`, `--json` output and exit codes, `version`.
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
