# `hecate-schema`

> Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.

| | |
|---|---|
| Module | `hecate.schema` |
| Rock | `hecate-schema` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | in progress (phase 2, steps 1, 2a, 2b and 3, plus `tagged_union`, `default`, `named`, `any` and `null`): type model, validation, JSON Schema emission (with the `pattern` translator, Lua pattern to ECMA-262) and coercion of textual inputs; class-bound instances (`build`, `sent`, PATCH) |
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
- `schema.enumeration(core_enumeration)`: the same constructor over a `core.enumeration`. The JSON representation of a value is its name (a member object is not JSON, a name round-trips through `json.encode` and `json.decode`): `validate` and `coerce` accept exactly the names (code `enum`, the names in `context.values`), the emission is `type` string with `enum`, and `build` replaces a name by the member (also inside objects, arrays, maps, unions, nullables and defaults; a default is given as a name). It is inlined; `schema.named` makes it a definition. The names are read once at declaration. A member object is never accepted as content.
- `schema.object(properties, { additional_properties })`: product type; undeclared properties are rejected by default.
- `schema.array(item, { min_items, max_items })`: sequences, 0-based pointer indices.
- `schema.optional(s)` (property may be absent), `schema.nullable(s)` (accepts `json.null`), `schema.union(list)`.
- `schema.tagged_union(tag, variants)`: discriminated sum (prefer it to a `union` of objects that differ by a literal: one dispatch on the tag, no re-validation); `variants` maps a name to an `object` schema, and the property `tag` holds the name (emitted as `oneOf`).
- `schema.default(s, value)`: property that may be absent; `s:coerce` (texts) and `s:build` (JSON content, every method except PATCH) supply a fresh deep copy of `value` for an absent property, also in nested objects, arrays, maps, unions and class-bound instances; an explicit `null` never takes it, `schema.sent` stays false for it and `validate` never supplies it; emitted as `default`. Recorded in OQ-88.
- `schema.of(Class|module)`: the primary way to name and reuse a schema. It is the schema of a class from its class-level `schema()`, resolved lazily; it is emitted once in `$defs` under the class name with a `$ref` at each use, with no declaration, and cycles close with `$ref` (recursive schemas). `schema.named(name, s)`: the secondary way, an explicit opt-in for an inline DTO that has no class; emitted like a class. A schema with neither a class nor `named` is inlined, never given a name. Two different bodies under one name in one emission (two `named`, or a `named` and a class) raise `ArgumentError` saying where each name comes from; equal bodies share one definition. `schema.any()` accepts every JSON value, `schema.null()` only `json.null`. Recorded in OQ-89.

Validation:

- `s:validate(value)` returns `true`, or `false` and the list of every `schema.Violation` (`path` as an RFC 6901 JSON Pointer, `code`, `message`, `context`).
- Nesting is bounded to 1000 levels, the maximum of `json.decode` and `json.encode`: a deeper value (only a hand-built table can be) yields a `depth_limit` violation at the path where validation stopped, never a stack overflow.
- Cost is bounded (OQ-91): the alternatives of a `union` are decided in a fail-fast mode (first violation, literal properties first), so a recursive `union` of discriminated containers costs linear work; `context.alternatives` is filled for the outermost failed union only (a union nested in an alternative has an empty list). Whatever the schema, a call spends at most 1,000,000 steps (one per container visited or alternative tried, shared by `validate`, `coerce` and `build`, reset on entry); beyond it the call ends with a `complexity_limit` violation (`context.max_steps`) at the path where it stopped. Within one call a `union` also remembers its answer per table node (validation verdict, coerced value), so even alternatives that nothing discriminates cost nodes times unions (depth 1000 of two identically shaped classes: about 0.01 s); the budget stays as the backstop. `tagged_union` remains the cheaper choice.
- `s:check(value)` returns the value or raises `core.ValidationError` with `context.violations`.

Instances (OQ-50, recorded in OQ-90):

- `s:build(content, { method, coerce })` validates decoded content and returns `true, value`, or `false` and the violations. A class-bound part (`schema.of(Class)`) becomes an instance of its class (allocated with `core.allocate`, so `init` is not called and may require arguments; then the declared attributes are assigned); when the class is a `value_class` its validated attributes are collected first and the frozen instance is made with `core.instantiate_value` (nested parts are built first; `init` is never called; `schema.sent` works on it); an absent or `null` attribute is nil. `method` is `"POST"`/`"PUT"` (strict, default) or `"PATCH"` (required properties of the top-level object may be absent; `null` fails unless nullable). `coerce = true` (a boolean, anything else raises `ArgumentError`) reads path, query and header texts: the content is converted with the rules of `coerce` first (a failed conversion gives the same `coercion` violations), then built; defaults apply once, in the conversion (never for PATCH), and `schema.sent` records only the attributes that were provided. Without `coerce`, or with `coerce = false`, nothing changes (OQ-93).
- A frozen instance of a value class keeps its attributes behind `__pairs`; the native encoder follows `__pairs` (OQ-94), so `json.encode` of a built instance writes an object of its attributes.
- `schema.sent(instance, name)`: true when the attribute was present in the content, explicit `null` included; kept in a weak-keyed side table outside the instance, so `pairs` and `json.encode` see only the attributes, and false (never raising) for a value not built by `build` (OQ-90).

Emission:

- `s:to_json_schema()` returns a JSON Schema 2020-12 document (plain values, `$schema` on the root). `pattern` raises `ArgumentError` (a Lua pattern has no exact ECMA-262 translation); `integer` and constants also accept float-valued numbers (`1.0`), which JSON Schema cannot exclude. Both are recorded in OQ-85.

Choices taken conservatively (Lua pattern for `pattern`, `integer` refuses `1.0`, and others) are in OQ-85.

## Layout (once implemented)

```text
src/hecate/schema/init.lua   public entry point
src/hecate/schema/schema.lua  Schema class and constructors, compiled validators
src/hecate/schema/violation.lua  Violation, JSON Pointer escaping
tests/unit/  tests/support/  tests/external.lua
examples/    benchmarks/
```

## Tests

- `tests/unit/` holds the unit tests and the differential tests (Lua validation against the emitted JSON Schema, read by the independent checker in `tests/support/conforms.lua`).
- `tests/unit/json_schema_suite_test.lua` runs the official JSON Schema test suite (dialect 2020-12, pinned in `tests/external.lua`, downloaded with `lua tools/run.lua fetch-fixtures schema`) over the supported subset, in three checks: the checker against the official `valid`, `Schema:validate` against it for the schemas that translate mechanically into a Hecate schema, and the emitted schema against `Schema:validate` on the official data. Groups outside the subset are skipped for an explicit reason listed in the file header, and the counts are printed on failure. The documented gaps are the `1.0` versus `integer` gap (OQ-85 point 11) and binary-float `multipleOf` with a fractional divisor; `pattern` and `format` groups are not run.
- Without the download the suite skips with a message on a developer machine and fails when the `CI` variable is set.
