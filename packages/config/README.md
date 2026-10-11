# `hecate-config`

> Layered configuration (defaults, environment files, environment variables, secrets) validated by schemas at boot.

| | |
|---|---|
| Module | `hecate.config` |
| Rock | `hecate-config` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`schema`](../schema) |
| Used by | `hecate`, `kernel` |
| Native code | none |
| Specification | [overview.md](../../docs/architecture/overview.md) |
| Decisions | — |
| Agent | [`pkg-config`](../../.claude/agents/pkg-config.md) |
| Repository | read-only mirror `hecate-framework/hecate-config`, generated from this directory (ADR 0017) |

## Responsibilities

- layers: `config/default.lua`, `config/<environment>.lua`, environment variables, secret files
- validation against declared schemas with precise diagnostics
- typed access
- secrets never logged

## Non-goals

- remote configuration services (later, by plugin)

## Standards and references

- The Twelve-Factor App (configuration)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/config/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
