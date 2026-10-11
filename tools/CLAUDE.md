# Agent context — `tools/`

Specialist agent: `ci-engineer`. Specification: `docs/architecture/automation.md`,
ADR 0015.

- Tasks live in `tools/tasks/<task>.lua` and export `{ description, run(args) }`.
- Tools may only use the Lua 5.5 standard library, LuaRocks-installed development rocks
  pinned in `tools/bootstrap/versions.lua`, and `tools/lib/`. They must not require
  Hecate packages (except `check-*` tasks that inspect them as files).
- Every new task: add it to the catalogue table in automation.md (status column), give it
  a `--json` report, test it on fixtures under `tools/tests/`.
- Workflows in `.github/workflows/` only call `tools/run.lua` tasks.
