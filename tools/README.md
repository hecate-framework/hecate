# Repository tools

Scripts that build, check, test, generate and release Hecate. Specification and
catalogue: [docs/architecture/automation.md](../docs/architecture/automation.md).

Run `lua tools/run.lua --list` for the tasks that exist; the catalogue, with the ones still planned,
is in [automation.md](../docs/architecture/automation.md). Tests of the tools:
`lua tools/run.lua test tools`.

## Layout

```text
tools/
  bootstrap/
    bootstrap.sh        Linux/macOS: Lua 5.5 + LuaRocks into .hecate/toolchain/
    bootstrap.ps1       Windows equivalent
    versions.lua        pinned versions and SHA-256 checksums of Lua, LuaRocks, dev rocks
  run.lua               task runner: lua tools/run.lua <task> [args] [--json]
  tasks/                one file per task (format.lua, lint.lua, check_boundaries.lua, ...)
  lib/                  shared helpers (rockspec parsing, git diff, dependency graph, reports,
                        and the logic of the coverage, sanitize, fuzz, leaks and licences tasks)
  harness/              bootstrap test harness (ADR 0008), removed after Phase 3
  hooks/                git hooks (install.lua installer; pre-commit.lua, commit-msg.lua bodies)
  services/compose.yaml database servers for local integration tests
```

## Conventions

- Lua 5.5, same coding standards as packages; no dependency on unreleased Hecate
  packages (tools must work before the framework does).
- Each task: `--help`, `--json`, exit code 0/1/2 (success/failure/usage error).
- Tasks are idempotent and runnable on Linux, macOS and Windows.
