<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Monorepo tooling: per-package rockspecs, a root task runner, formatter, linter, LuaLS configuration (`.luarc.json`), test runner bootstrap (temporary harness until `hecate.test` exists, see ADR 0008).
- status: in-progress
- lock_until: 2026-10-12T12:50:58Z
- last_update: 2026-10-12T11:20:58Z

## Done

- Claimed the item (branch, draft PR). Issue #9 (relay blocked on PR #8) is obsolete: PR #8 and #10 are merged.
- Step 2: `tools/run.lua` (`--list`, `--help`, `--json`, exit 0/1/2), `tools/lib/util.lua`, task `check-package-structure`.
- Step 3: task `gen-rockspecs`; 29 rockspecs (builtin, empty modules; dependencies from the README "Depends on" row) and `tests/.gitkeep`. The meta-rock is named `hecate` (`hecate-scm-1.rockspec`). CHANGELOG entry added.
- Step 4: tasks `check-versions` (lua range and package name; the VERSION check is added at release time) and `check-rockspecs` (`luarocks lint` and dependency names). All pass.

## Next steps

1. `tools/tests` fixtures for `run.lua`; update `tools/README.md` and the automation.md status column.
2. `.luarc.json`, `typecheck` task, `lint` task, `format` task (OQ-3: owner choice pending, record only).
3. Temporary test harness `tools/harness` (ADR 0008) and `test` task.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- Meta-rock `hecate` source url points at the monorepo URL (no mirror named `hecate`); native packages have empty `modules` until their C code exists.
- Branch: the session was assigned claude/sweet-feynman-765b90, but relay.md requires claude/relay-<slug>; relay.md followed.

## Commands to re-run

```sh
lua tools/run.lua --list
lua tools/run.lua check-package-structure
```
