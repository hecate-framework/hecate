# `hecate-schema`

> Refinement types, composition, coercion and validation with JSON Pointer error paths; emits JSON Schema 2020-12.

| | |
|---|---|
| Module | `hecate.schema` |
| Rock | `hecate-schema` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | implemented (phase 2): type model, validation, coercion, JSON Schema 2020-12 emission with the `pattern` translator, `map`, `multiple_of`, `format`, `tagged_union`, `default`, `named`, `any`, `null`, class-bound instances (`of`, `build`, `sent`, PATCH, `coerce = true`), enumerations of `core`, bounded depth and cost, and the official JSON Schema test suite over the supported subset. Documented in a how-to, an explanation page and tested examples. Not yet implemented, planned: `refine` (OQ-97), `generate` and `generate_invalid` (carried by `test`) and `---@meta` generation (carried by `doc` or `cli`). Remaining limits: no lazy `named` for recursion without a class, formats limited to `uuid`, `date`, `date-time`, `email`, `ipv4` and `uri`, `multiple_of` with whole divisors only |
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
- JSON Schema emission

Planned, not implemented here: `---@meta` generation for LuaLS (carried by `doc` or `cli`) and generators for
property-based testing (carried by `test`). `refine` is not offered (OQ-97).

## Non-goals

- persistence metadata (see `orm`)

## Standards and references

- JSON Schema 2020-12
- RFC 6901
- RFC 3339 (date-time)

## Public API

Declarations (`local schema = require("hecate.schema")`); every schema is an immutable value (`schema.Schema`):

- `schema.string({ min_length, max_length, pattern, format, logger })`, `schema.integer({ minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of })`, `schema.number({ minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of })`, `schema.boolean()`: base types and refinements (option classes `StringOptions`, `IntegerOptions`, `NumberOptions`). `pattern` is a Lua pattern, translated to ECMA-262 on emission (subset in the specification; `%b`, `%f`, `()` and non-ASCII bytes are refused, with a message that says Lua validation is unaffected and how to rewrite). `format` is `uuid`, `date`, `date-time`, `email` (no control character, at most 254 bytes), `ipv4` or `uri`; an unknown one is refused with the list of accepted formats. `logger` (any object with `warning(message, fields)`, for example a `hecate.log` logger; OQ-86) receives `schema: pattern "..." cannot be emitted: <reason>` at declaration when `pattern` cannot be emitted; with no `logger` nothing is reported until emission. A malformed `pattern` (for example `ab%`, `(a`, `[a`) is refused at declaration with `ArgumentError`; a match that Lua still gives up on ("pattern too complex") is a `pattern` violation with `context.reason = "malformed_pattern"`, never a raw error. `pattern` and `format` are not run on a value that already has an `invalid_utf8` or `max_length` violation, and, when no `max_length` is declared, not on a string longer than 65536 bytes: that string gets a `pattern` (or `format`) violation with `context.reason = "too_long_for_pattern"`. Lua patterns can backtrack, so anchor them (`^` and `$`) and declare `max_length`. `multiple_of` takes a whole-number divisor only (OQ-87): for decimals, use integers in minor units or a string with a `pattern`. An unknown option is refused with the list of accepted options.
- `schema.map(value, { min_properties, max_properties })`: string keys not declared in advance (no key schema, OQ-87).
- `schema.literal(value)`, `schema.enumeration(values)`: constants (JSON Schema `const` and `enum`).
- `schema.enumeration(core_enumeration)`: the same constructor, which takes a list of constants or a `core.enumeration`. The JSON representation of a value is its name (a member object is not JSON, a name round-trips through `json.encode` and `json.decode`): `validate` and `coerce` accept exactly the names (code `enum`, the names in `context.values`), the emission is `type` string with `enum`, and `build` replaces a name by the member (also inside objects, arrays, maps, unions, nullables and defaults; a default is given as a name). It is inlined; `schema.named` makes it a definition. The names are read once at declaration. A member object is never accepted as content.
- `schema.object(properties, { additional_properties })`: product type; undeclared properties are rejected by default (violation `additional_properties`).
- `schema.array(item, { min_items, max_items, delimiter, unique_items })`: sequences, 0-based pointer indices; `delimiter` (default `","`, not empty) is how `coerce` splits a text, `unique_items` refuses two equal items (violation `unique_items`).
- `schema.optional(inner)` (property may be absent), `schema.nullable(inner)` (accepts `json.null`), `schema.union(alternatives)` (`anyOf`). A union must not contain null: `nullable` is the only way for a property to accept null, so `union` refuses at declaration, with `ArgumentError`, every alternative that accepts null: `schema.null()`, a `nullable` schema, `schema.literal(json.null)` and an `schema.enumeration` whose constants contain `json.null`, also under `named`, `optional` or `default`; write `nullable(union(...))` instead (OQ-99, OQ-100). A literal null or such an enumeration stays allowed as a plain property. It is a declaration error, not a violation code. `schema.any()` is not refused: it accepts every value, null included, by an explicit choice. Parameter names follow the role: `item`, `value`, `inner`, `alternatives`.
- `schema.tagged_union(tag, variants)`: discriminated sum (prefer it to a `union` of objects that differ by a literal: one dispatch on the tag, no re-validation); `variants` maps a name to an `object` schema, and the property `tag` holds the name (emitted as `oneOf`).
- `schema.default(inner, value)`: property that may be absent; `s:coerce` (texts) and `s:build` (JSON content, every method except PATCH) supply a fresh deep copy of `value` for an absent property, also in nested objects, arrays, maps, unions and class-bound instances; an explicit `null` never takes it, `schema.sent` stays false for it and `validate` never supplies it; emitted as `default`. Recorded in OQ-88. The stored value lives in a closure: `s.options` does not expose it, and only copies are handed out.
- `schema.of(Class|module)`: the primary way to name and reuse a schema. It is the schema of a class from its class-level `schema()`, resolved lazily; it is emitted once in `$defs` under the class name with a `$ref` at each use, with no declaration, and cycles close with `$ref` (recursive schemas). `schema.named(name, inner)`: the secondary way, an explicit opt-in for an inline schema that has no class; emitted like a class. A schema with neither a class nor `named` is inlined, never given a name. Two different definitions under one name in one emission (two `named`, or a `named` and a class) raise `ArgumentError` saying where each name comes from; equal bodies share one definition. A declared property whose name is a member of the class (a method, an inherited method, a name starting with `__`) is refused with `ArgumentError` at first use, naming the class and the property: the instance and `represent` would confuse them. A plain field on the class (a prototype value) is allowed, but it is never represented. `schema.any()` accepts every JSON value, `schema.null()` only `json.null`. Recorded in OQ-89.

- `schema.Representable`: the interface of a class whose instances have a representation; it requires the class-level `schema()`. A class that declares it (`implements = { schema.Representable }`) without `schema` raises `ConformanceError` at finalisation. `schema.of` refuses a class that does not declare it, even one that has `schema()`: `ArgumentError` naming the class and the interface, raised at declaration for a finalised class and at first use otherwise (also for the module name form).

Return conventions: `validate` returns `true`, or `false` and the violations; `coerce` and `build` return `true, value` or `false, violations` (never raise for content that does not conform); `check` is the raising form of `validate` only.

Violation codes are stable and listed, with their context fields, in the specification ([Violation codes](../../docs/architecture/schemas-and-contracts.md#violation-codes)); `Violation.code` has the type `hecate.schema.ViolationCode`. `additional_properties` is the code for an undeclared property.

Validation:

- `s:validate(value)` returns `true`, or `false` and the list of every `schema.Violation` (`path` as an RFC 6901 JSON Pointer, `code`, `message`, `context`).
- Nesting is bounded to 1000 levels, the maximum of `json.decode` and `json.encode`: a deeper value (only a hand-built table can be) yields a `depth_limit` violation at the path where validation stopped, never a stack overflow.
- Cost is bounded (OQ-91): the alternatives of a `union` are decided in a fail-fast mode (first violation, literal properties first), so a recursive `union` of discriminated containers costs linear work; `context.alternatives` is filled for the outermost failed union only (a union nested in an alternative has an empty list). `unique_items` hashes scalar items and compares only tables of the same shallow signature, and charges one step per item hashed and per comparison. A call keeps at most 100 violations: the 101st is replaced by one `too_many_violations` violation (`context.max = 100`), validators stop descending, and a property name echoed in a violation path or context is cut to 64 bytes. Whatever the schema, a call spends at most 1,000,000 steps (one per container visited or alternative tried, shared by `validate`, `coerce` and `build`, reset on entry); beyond it the call ends with a `complexity_limit` violation (`context.max_steps`) at the path where it stopped. Within one call a `union` also remembers its answer per table node (validation verdict, coerced value), so even alternatives that nothing discriminates cost nodes times unions (depth 1000 of two identically shaped classes: about 0.01 s); the budget stays as the backstop. `tagged_union` remains the cheaper choice.
- `s:check(value)` returns the value or raises `core.ValidationError` with `context.violations` (the raising form of `validate`).

Instances (OQ-50, recorded in OQ-90):

- `s:build(content, { method, coerce })` validates decoded content and returns `true, value`, or `false` and the violations. A class-bound part (`schema.of(Class)`) becomes an instance of its class (allocated with `core.allocate`, so `init` is not called and may require arguments; then the declared attributes are assigned); when the class is a `value_class` its validated attributes are collected first and the frozen instance is made with `core.instantiate_value` (nested parts are built first; `init` is never called; `schema.sent` works on it); an absent or `null` attribute is nil. `method` is `"POST"`/`"PUT"` (strict, default) or `"PATCH"` (required properties of the top-level object may be absent; `null` fails unless nullable). `coerce = true` (a boolean, anything else raises `ArgumentError`) reads path, query and header field texts: the content is converted with the rules of `coerce` first (a failed conversion gives the same `coercion` violations), then built; defaults apply once, in the conversion (never for PATCH), and `schema.sent` records only the attributes that were provided. Without `coerce`, or with `coerce = false`, nothing changes (OQ-93).
- A frozen instance of a value class keeps its attributes behind `__pairs`; the native encoder follows `__pairs` (OQ-94), so `json.encode` of a built instance writes an object of its attributes.
- `s:represent(value)`: the representation of an instance for a response (OQ-95): plain, JSON-ready values in fresh tables, to be given to `json.encode`. A class-bound part (class or `value_class`) becomes a table of the attributes its schema declares and only those (an undeclared attribute never appears); a `core` enumeration member becomes its name; nested parts, arrays (marked with `json.array`, so an empty one is `[]`), maps and objects (marked with `json.object`, `{}`), unions (the alternative that accepts the value, decided in fail-fast mode, memoised per node) and tagged unions (the tag selects the variant) convert recursively; `named`, `any` (a deep copy) and `null` work. An absent attribute is omitted, `json.null` stays null, defaults are not applied, nothing is validated except to choose a union alternative. Only the fields of the instance itself are read (never a method or a prototype field of its class), and a function value is skipped. A nullable attribute that is nil on an instance made by `build` and was sent as `null` is represented as `null` (the presence set), so that decode, build, represent and encode give back the content; an instance that was not built has sent nothing, and its nil attributes are omitted. The input is not modified. The depth guard and the work budget are those of `validate`; a cycle, a table too deep or too costly raises `ValidationError` with one violation (`context.violations`: `depth_limit`, `complexity_limit`, `union`, `tagged_union`, `enum` or `type`) at the JSON Pointer where it stopped. Representers are compiled closures made at declaration, like the validators.
- `schema.sent(instance, name)`: true when the attribute was present in the content, explicit `null` included; kept in a weak-keyed side table outside the instance, so `pairs` and `json.encode` see only the attributes, and false (never raising) for a value not built by `build` (OQ-90).

Emission:

- `s:to_json_schema()` returns a JSON Schema 2020-12 document (plain values, `$schema` on the root). `pattern` is translated to ECMA-262; a pattern outside the exact subset raises `ArgumentError`. `integer` and constants also accept float-valued numbers (`1.0`), which JSON Schema cannot exclude (OQ-85, point 11).

Limits:

- `unique_items` compares tables structurally down to the depth guard (`json.DEFAULT_MAX_DEPTH`, 1000 levels); two tables still different tables below that depth, which only a hand-built value can reach, are treated as different, never by a Lua stack overflow (OQ-99).
- Per-call state: the validators, coercers, builders and representers keep their counters and caches (depth, work budget, memoisation) in module-level state that each public call resets at its start. A metamethod of a user object (an `__index` or `__pairs`) that yields during a call could therefore interleave two calls running in different coroutines. Such metamethods must not suspend (OQ-99).

JSON Schema keywords outside the emitted subset are a deliberate limit, out of scope until a consumer needs them: `allOf`, `not`, `if`, `then` and `else`, `contains`, `prefixItems`, `patternProperties`, `propertyNames`, `dependentSchemas`, `dependentRequired`, `unevaluatedProperties`, `unevaluatedItems`, `$id`, anchors, `$dynamicRef`, remote `$ref` and the `content` keywords. `oneOf` is emitted only by `tagged_union`; a `union` is `anyOf`.

Not offered: `refine(base, predicate, description)` (OQ-97). Not yet implemented, planned: `generate` and `generate_invalid` (property-based generators, carried by `test`) and `---@meta` generation for LuaLS (carried by `doc` or `cli`).

Documentation: the how-to [Validate values with schemas](../../website/en/how-to/validate-with-schemas.md), the explanation [Schemas and contracts](../../website/en/explanation/schemas-and-contracts.md) and the tested examples in `examples/`.

Choices taken conservatively (Lua pattern for `pattern`, `integer` refuses `1.0`, and others) are in OQ-85.

## Layout

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
