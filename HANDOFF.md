<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Monorepo tooling: per-package rockspecs, a root task runner, formatter, linter, LuaLS configuration (`.luarc.json`), test runner bootstrap (temporary harness until `hecate.test` exists, see ADR 0008).
- status: in-progress
- lock_until: 2026-10-12T12:44:45Z
- last_update: 2026-10-12T11:14:45Z

## Done

- Claimed the item (branch, draft PR). Issue #9 (relay blocked on PR #8) is obsolete: PR #8 and #10 are merged.

## Next steps

0. Add tools/tests fixtures for run.lua; update tools/README.md and automation.md status; CHANGELOG [Unreleased].
3. Per-package rockspecs generated from package READMEs; check-rockspecs and check-package-structure tasks.
4. .luarc.json, lint/typecheck/format tasks (formatter per OQ-3: needs owner choice, record in open-questions).
5. Temporary test harness (tools/harness) per ADR 0008.

- Step 2: tools/run.lua (--list, --help, --json, exit 0/1/2), tools/lib/util.lua, task check-package-structure (reports 58 expected problems: every package lacks rockspec + tests/).

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- Branch: the session was assigned claude/sweet-feynman-765b90, but relay.md requires claude/relay-<slug>; relay.md followed.

## Commands to re-run

```sh
lua tools/run.lua --list
lua tools/run.lua check-package-structure
```
