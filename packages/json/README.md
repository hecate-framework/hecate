# `hecate-json`

> Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and streaming.

| | |
|---|---|
| Module | `hecate.json` |
| Rock | `hecate-json` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `cli`, `doc`, `hecate`, `http`, `kernel`, `log`, `openapi`, `schema`, `security`, `test` |
| Native code | C codec (OQ-5) |
| Specification | [schemas-and-contracts.md](../../docs/architecture/schemas-and-contracts.md) |
| Decisions | — |
| Agent | [`pkg-json`](../../.claude/agents/pkg-json.md) |
| Repository | read-only mirror `hecate-framework/hecate-json`, generated from this directory (ADR 0017) |

## Responsibilities

- `encode`, `decode`, pretty printing, canonical key ordering option
- `json.null`, `json.array` markers resolving Lua table ambiguity
- integer versus float preservation (Lua 5.5 integer subtype)
- incremental decoder for large bodies
- precise error positions

## Non-goals

- schema validation (see `schema`)

## Standards and references

- RFC 8259
- RFC 6901 (JSON Pointer)
- I-JSON, RFC 7493

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/json/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
