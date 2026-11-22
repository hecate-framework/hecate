# `hecate-cli`

> The `hecate` command: toolchains, projects, dependencies (LuaRocks), development server, tests, contracts, documentation, migrations, scaffolding, packaging.

| | |
|---|---|
| Module | `hecate.cli` |
| Rock | `hecate-cli` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | in progress — dispatcher, argument parser, `--help`, `--json`, exit codes and `version`; other commands to do |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`json`](../json), [`schema`](../schema) |
| Used by | — |
| Native code | self-contained executable embedding Lua 5.5 and what the CLI itself needs (OQ-13) |
| Specification | [cli-and-packaging.md](../../docs/architecture/cli-and-packaging.md) |
| Decisions | [ADR 0009](../../docs/adr/0009-project-manifest.md), [ADR 0010](../../docs/adr/0010-self-contained-cli-and-managed-toolchains.md) |
| Agent | [`pkg-cli`](../../.claude/agents/pkg-cli.md) |
| Repository | read-only mirror `hecate-framework/hecate-cli`, generated from this directory (ADR 0017) |

## Responsibilities

- all commands in cli-and-packaging.md
- manifest evaluation in a sandbox and validation
- lockfile generation and verification
- LuaRocks orchestration with isolated configuration
- toolchain installation per platform
- project templates
- workflow generation (`hecate generate workflow ci|contract|docs-pages|release`), including publication of the documentation to GitHub Pages
- `--json` output for every command

## Non-goals

- replacing LuaRocks
- carrying the framework: `kernel`, `test`, `doc`, `openapi`, `migration` and the drivers are dependencies of the
  user's project, installed by `hecate install` and run by the project's interpreter; the `hecate` executable starts
  that interpreter and loads none of them (owner decision of 2026-11-14, [spike OQ-13](../../docs/spikes/OQ-13-standalone-executable.md))

## Standards and references

- sha256 through the `digest` rock behind a one-module seam, [ADR 0028](../../docs/adr/0028-cli-sha256-rock-behind-a-seam.md)
- LuaRocks rockspec format
- SemVer 2.0.0

## Public API

- `cli.run(args, options)`: runs one command line, returns the exit code (0 ok, 1 command failed, 2 usage error).
- `cli.parse(args, commands)`: global flags, command selection (one or two words) and options, raising `ArgumentError`.
- `cli.commands`: the commands implemented so far (`version`).
- `hecate.cli.Command`: `name`, `summary`, `usage`, `options`, `run(context)`; `Context:emit(value, text)` prints JSON under `--json`.

## Layout (once implemented)

```text
src/hecate/cli/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
