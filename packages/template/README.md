# `hecate-template`

> Compiled templates with contextual auto-escaping, for HTML and text responses.

| | |
|---|---|
| Module | `hecate.template` |
| Rock | `hecate-template` |
| Layer | Framework |
| Roadmap phase | 5 |
| Status | planned — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`kernel`](../kernel) |
| Used by | — |
| Native code | none |
| Specification | [roadmap.md](../../docs/roadmap.md) |
| Decisions | — |
| Agent | [`pkg-template`](../../.claude/agents/pkg-template.md) |
| Repository | read-only mirror `hecate-framework/hecate-template`, generated from this directory (ADR 0017) |

## Responsibilities

- compilation to Lua functions
- contextual escaping
- layouts, partials, components as classes

## Non-goals

- client-side rendering

## Standards and references

- HTML Living Standard (escaping contexts)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/template/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
