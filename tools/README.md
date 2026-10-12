# Repository tools

Scripts that build, check, test, generate and release Hecate. Specification and
catalogue: [docs/architecture/automation.md](../docs/architecture/automation.md).

Implemented so far: `run.lua`, `harness/`, and the tasks `check-package-structure`,
`check-versions`, `check-rockspecs`, `gen-rockspecs`, `lint`, `typecheck` (needs
`lua-language-server` on `PATH`), `test [packages|tools]`, `format` and `format-check`
(no-ops, see OQ-3). Run `lua tools/run.lua --list`. Tests of the tools: `lua tools/run.lua test tools`.

## Planned layout

```text
tools/
  bootstrap/
    bootstrap.sh        Linux/macOS: Lua 5.5 + LuaRocks into .hecate/toolchain/
    bootstrap.ps1       Windows equivalent
    versions.lua        pinned versions and SHA-256 checksums of Lua, LuaRocks, dev rocks
  run.lua               task runner: lua tools/run.lua <task> [args] [--json]
  tasks/                one file per task (format.lua, lint.lua, check_boundaries.lua, ...)
  lib/                  shared helpers (rockspec parsing, git diff, dependency graph, reports)
  harness/              bootstrap test harness (ADR 0008), removed after Phase 3
  hooks/                git hooks and their installer
  services/compose.yaml database servers for local integration tests
```

## Conventions

- Lua 5.5, same coding standards as packages; no dependency on unreleased Hecate
  packages (tools must work before the framework does).
- Each task: `--help`, `--json`, exit code 0/1/2 (success/failure/usage error).
- Tasks are idempotent and runnable on Linux, macOS and Windows.
