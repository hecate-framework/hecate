<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Monorepo tooling: per-package rockspecs, a root task runner, formatter, linter, LuaLS configuration (`.luarc.json`), test runner bootstrap (temporary harness until `hecate.test` exists, see ADR 0008).
- status: in-progress
- lock_until: 2026-10-12T12:50:58Z
- last_update: 2026-10-12T11:20:58Z

## Done

- Claimed the item (branch, draft PR). Issue #9 (relay blocked on PR #8) is obsolete: PR #8 and #10 are merged.

## Next steps

1. tools/tests fixtures for run.lua; update tools/README.md and automation.md status column.
3. .luarc.json + typecheck task; lint task; format task (OQ-3: owner choice pending, record only).
4. Temporary test harness tools/harness (ADR 0008) and `test` task.
- Step 4: tasks check-versions (scm-1 rockspecs: lua range + package name; VERSION release-version check to add at release time) and check-rockspecs (luarocks lint + dependency names). Both pass.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- Meta-rock `hecate` source url points at the monorepo URL (no mirror named `hecate`); native packages have empty `modules` until their C code exists.
- Branch: the session was assigned claude/sweet-feynman-765b90, but relay.md requires claude/relay-<slug>; relay.md followed.

## Commands to re-run

```sh
lua tools/run.lua --list
lua tools/run.lua check-package-structure
```
