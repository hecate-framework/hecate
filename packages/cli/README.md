# `hecate-cli`

> The `hecate` command: toolchains, projects, dependencies (LuaRocks), development server, tests, contracts, documentation, migrations, scaffolding, packaging.

| | |
|---|---|
| Module | `hecate.cli` |
| Rock | `hecate-cli` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`json`](../json), [`schema`](../schema), [`kernel`](../kernel), [`test`](../test), [`doc`](../doc), [`openapi`](../openapi), [`migration`](../migration) |
| Used by | — |
| Native code | self-contained executable embedding Lua 5.5 (OQ-13) |
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

## Standards and references

- LuaRocks rockspec format
- SemVer 2.0.0

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/cli/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
