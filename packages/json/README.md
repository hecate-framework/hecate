# `hecate-json`

> Fast, correct JSON codec (RFC 8259) with integer/float fidelity, explicit null and array markers, and streaming.

| | |
|---|---|
| Module | `hecate.json` |
| Rock | `hecate-json` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | first slice: Lua API and pure-Lua reference backend; native backends, streaming decoder, conformance corpus and fuzzing to come |
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

```lua
local json = require("hecate.json")
```

| Name | Description |
|---|---|
| `json.encode(value, options?)` | Encodes a Lua value as JSON text that is always valid UTF-8. Options: `pretty`, `indent` (spaces or a string of spaces and tabs), `canonical` (members in byte order), `max_depth` (default 1000, at most 10000), `max_size` (default 16 MiB). |
| `json.decode(text, options?)` | Decodes JSON text (RFC 8259). Options: `max_depth`, `max_size`. |
| `json.null` | The value of JSON `null` (unique, immutable, never `nil`). |
| `json.array(t?)`, `json.object(t?)` | Mark a table as a JSON array or object (a new empty table without argument); return the table. |
| `json.is_array(v)`, `json.is_object(v)` | Tell whether a value carries a marker. |
| `json.JsonError`, `json.DecodeError`, `json.EncodeError` | Errors on the `hecate.core` hierarchy, with stable codes `hecate.json.*`. |

Value model (the same for every backend, ADR 0020):

- A Lua integer is a JSON integer; a float is always written with a decimal point or an
  exponent, so `1.0` stays a float. NaN and the infinities raise `EncodeError`.
- An integer literal that does not fit in 64 bits decodes as a float; `-0` decodes as `-0.0`.
- `decode` returns every array marked with `json.array` and every object marked with
  `json.object`; an empty `[]` and an empty `{}` therefore round-trip.
- On encoding, an unmarked table is an array when its keys are exactly 1 to n, an object when
  all keys are strings, an **object when empty**, and an error otherwise (OQ-48).
- `decode` rejects invalid UTF-8, lone surrogate escapes, duplicate member names, a byte order
  mark, trailing content and nesting deeper than `max_depth`.

Errors: `DecodeError.context` has `reason`, `offset` (bytes before the offending byte, from 0),
`line` and `column` (from 1, in characters); `EncodeError.context` has `reason` and `path` (a JSON
Pointer, RFC 6901). Backends: the native module `hecate.json.native` (not built yet) is used when
present, otherwise the pure-Lua reference backend `hecate.json.internal.reference`, which is also
the test oracle; callers cannot tell them apart.

## Layout (once implemented)

```text
src/hecate/json/init.lua   public entry point
src/hecate/json/errors.lua error classes
src/hecate/json/internal/  markers, backend seam, reference backend, error positions
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
