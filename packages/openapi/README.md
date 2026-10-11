# `hecate-openapi`

> OpenAPI 3.1 document assembly from the route table, schemas and project settings; served endpoint, export, lint and breaking-change diff.

| | |
|---|---|
| Module | `hecate.openapi` |
| Rock | `hecate-openapi` |
| Layer | 3 — Framework |
| Roadmap phase | 3 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`schema`](../schema), [`router`](../router), [`json`](../json) |
| Used by | `cli`, `doc`, `hecate`, `test` |
| Native code | none |
| Specification | [schemas-and-contracts.md](../../docs/architecture/schemas-and-contracts.md) |
| Decisions | [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md) |
| Agent | [`pkg-openapi`](../../.claude/agents/pkg-openapi.md) |
| Repository | read-only mirror `hecate-framework/hecate-openapi`, generated from this directory (ADR 0017) |

## Responsibilities

- document assembly (info, servers, paths, components, security)
- `/openapi.json` and an interactive reference page in development
- export to JSON/YAML
- contract diff with breaking-change classification
- lint rules (operation ids, descriptions, examples)

## Non-goals

- client code generation (later)

## Standards and references

- OpenAPI 3.1
- JSON Schema 2020-12

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/openapi/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
