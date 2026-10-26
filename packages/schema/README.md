# `hecate-schema`

> Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.

| | |
|---|---|
| Module | `hecate.schema` |
| Rock | `hecate-schema` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`json`](../json) |
| Used by | `cli`, `config`, `doc`, `hecate`, `kernel`, `openapi`, `orm`, `security`, `test` |
| Native code | none |
| Specification | [schemas-and-contracts.md](../../docs/architecture/schemas-and-contracts.md) |
| Decisions | [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md) |
| Agent | [`pkg-schema`](../../.claude/agents/pkg-schema.md) |
| Repository | read-only mirror `hecate-framework/hecate-schema`, generated from this directory (ADR 0017) |

## Responsibilities

- base types and refinement types (`integer { minimum = 1 }`, `string { format = "email" }`)
- product types (`object`), sum types (`union`, tagged union), `array`, `map`, `literal`, `enumeration`, `optional`, `nullable`
- coercion of textual inputs (path, query, fields)
- validation with all errors collected, JSON Pointer paths
- JSON Schema emission and `---@meta` generation for LuaLS
- generators for property-based testing (used by `test`)

## Non-goals

- persistence metadata (see `orm`)

## Standards and references

- JSON Schema 2020-12
- RFC 6901
- RFC 3339 (date-time)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/schema/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
