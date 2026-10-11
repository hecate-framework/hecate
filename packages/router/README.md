# `hecate-router`

> Radix-tree router over URI templates (RFC 6570 level-1 subset) with 404/405 handling and reverse routing.

| | |
|---|---|
| Module | `hecate.router` |
| Rock | `hecate-router` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `hecate`, `kernel`, `openapi` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md) |
| Agent | [`pkg-router`](../../.claude/agents/pkg-router.md) |
| Repository | read-only mirror `hecate-framework/hecate-router`, generated from this directory (ADR 0017) |

## Responsibilities

- compile route tables into a radix tree at boot
- static > parameter > wildcard precedence
- `Allow` field for 405
- reverse routing (URI generation from route name and parameters)
- route table introspection

## Non-goals

- parameter validation (done by kernel with `schema`)

## Standards and references

- RFC 6570 (URI Template)
- RFC 3986 (URI)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/router/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
