# `hecate`

> Meta-rock `hecate`: depends on the standard edition and provides the `hecate` meta-module re-exporting the framework surface.

| | |
|---|---|
| Module | `hecate` |
| Rock | `hecate` |
| Layer | Meta |
| Roadmap phase | 3 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`json`](../json), [`log`](../log), [`http`](../http), [`schema`](../schema), [`router`](../router), [`container`](../container), [`config`](../config), [`kernel`](../kernel), [`openapi`](../openapi) |
| Used by | — |
| Native code | none |
| Specification | [overview.md](../../docs/architecture/overview.md) |
| Decisions | [ADR 0005](../../docs/adr/0005-single-brand-monorepo-lockstep-versioning.md) |
| Agent | [`pkg-hecate`](../../.claude/agents/pkg-hecate.md) |
| Repository | built from the monorepo (no mirror, ADR 0017) |

## Responsibilities

- single dependency for typical applications
- `require "hecate"` gives classes, controllers, routes, problems, schema shortcuts

## Non-goals

- code of its own beyond re-exports

## Standards and references

- —

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
