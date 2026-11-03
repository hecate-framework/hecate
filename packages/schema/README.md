# `hecate-schema`

> Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.

| | |
|---|---|
| Module | `hecate.schema` |
| Rock | `hecate-schema` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | in progress (phase 2, steps 1, 2a, 2b and 3, plus `tagged_union`, `default`, `named`, `any` and `null`): type model, validation, JSON Schema emission (with the `pattern` translator, Lua pattern to ECMA-262) and coercion of textual inputs; instances to come |
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

Declarations (`local schema = require("hecate.schema")`); every schema is an immutable value (`schema.Schema`):

- `schema.string{ min_length, max_length, pattern }`, `schema.integer{ minimum, maximum }`, `schema.number{ minimum, maximum }`, `schema.boolean()`: base types and refinements.
- `schema.literal(value)`, `schema.enumeration(values)`: constants (JSON Schema `const` and `enum`).
- `schema.object(properties, { additional_properties })`: product type; undeclared properties are rejected by default.
- `schema.array(item, { min_items, max_items })`: sequences, 0-based pointer indices.
- `schema.optional(s)` (property may be absent), `schema.nullable(s)` (accepts `json.null`), `schema.union(list)`.
- `schema.tagged_union(tag, variants)`: discriminated sum; `variants` maps a name to an `object` schema, and the property `tag` holds the name (emitted as `oneOf`).
- `schema.default(s, value)`: property that may be absent; `s:coerce` supplies a copy of `value`, `validate` does not; emitted as `default`. Both are recorded in OQ-88.
- `schema.of(Class|module)`: the schema of a class from its class-level `schema()`, resolved lazily; cycles close with `$ref` (recursive schemas). `schema.named(name, s)`: gives `s` a name; emitted once in `$defs` and referenced with `$ref`. `schema.any()` accepts every JSON value, `schema.null()` only `json.null`. Recorded in OQ-89.

Validation:

- `s:validate(value)` returns `true`, or `false` and the list of every `schema.Violation` (`path` as an RFC 6901 JSON Pointer, `code`, `message`, `context`).
- `s:check(value)` returns the value or raises `core.ValidationError` with `context.violations`.

Emission:

- `s:to_json_schema()` returns a JSON Schema 2020-12 document (plain values, `$schema` on the root). `pattern` raises `ArgumentError` (a Lua pattern has no exact ECMA-262 translation); `integer` and constants also accept float-valued numbers (`1.0`), which JSON Schema cannot exclude. Both are recorded in OQ-85.

Choices taken conservatively (Lua pattern for `pattern`, `integer` refuses `1.0`, and others) are in OQ-85.

## Layout (once implemented)

```text
src/hecate/schema/init.lua   public entry point
src/hecate/schema/schema.lua  Schema class and constructors, compiled validators
src/hecate/schema/violation.lua  Violation, JSON Pointer escaping
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
