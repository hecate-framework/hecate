---
description: Every constructor and option of hecate.schema, the JSON Schema 2020-12 keyword each one emits, the supported format values and the violation codes.
hecate: "0.x"
lua: "5.5"
order: 2
---

<!-- Hand-written reference page (not generated): keep it in step with packages/schema/README.md and
docs/architecture/schemas-and-contracts.md. -->

# Schema keywords and formats

This page lists what `hecate.schema` accepts, for hecate 0.x and Lua 5.5. For each constructor, it gives the
options, the JSON Schema 2020-12 keyword emitted, and the violation code. It also lists the values of `format`. For
how to use them, read [Validate values with schemas](../how-to/validate-with-schemas.md).

A [schema](glossary.md#types-and-validation) is the declaration of a type, usable for validation, coercion and
contract emission. You build one with a constructor and its options. The same schema then validates values and emits
JSON Schema:

```lua
local schema = require("hecate.schema")

local age = schema.integer({ minimum = 0 })
print(age:to_json_schema().minimum)
-- Prints: 0
local ok, violations = age:validate(-1)
print(ok, violations[1].code)
-- Prints: false	minimum
```

Options follow the JSON Schema vocabulary in `snake_case` ([glossary](glossary.md#types-and-validation)):
`minimum` above, `min_length`, `multiple_of`.

Options are checked at declaration. Each of these raises `hecate.core.ArgumentError`, with the list of accepted
options:

- an unknown option;
- an option of the wrong type;
- an inconsistent range (`minimum` above `maximum`).

## Base types

| Constructor | Accepts | Emits |
|---|---|---|
| `schema.string(options?)` | a Lua string | `type: string` |
| `schema.integer(options?)` | a Lua integer; `1.0` and `1.5` are refused | `type: integer` |
| `schema.number(options?)` | any Lua number | `type: number` |
| `schema.boolean()` | `true`, `false` | `type: boolean` |
| `schema.null()` | `json.null` only | `type: null` |
| `schema.any()` | every value, `json.null` included | `{}` (no constraint) |

## String options

| Option | Type | Emits | Violation code |
|---|---|---|---|
| `min_length` | integer | `minLength` | `min_length` |
| `max_length` | integer | `maxLength` | `max_length` |
| `pattern` | Lua pattern | `pattern`, translated to ECMA-262 | `pattern` |
| `format` | one of the formats below | `format` | `format` |
| `logger` | object with `warning(message, fields)` | nothing | none |

Lengths count UTF-8 characters. When a length is declared, a string that is not valid UTF-8 gets the violation
`invalid_utf8`.

`pattern` is a Lua pattern, not a regular expression. Anchor it (`^...$`) and declare `max_length`, because a Lua
pattern can backtrack.

The emission translates a subset of Lua patterns exactly. It refuses the rest with an `ArgumentError` at emission:

- `%b`;
- `%f`;
- the position capture `()`;
- non-ASCII bytes.

A malformed pattern (`ab%`, `(a`, `[a`) is refused earlier, at declaration.

`logger` receives, at declaration, a warning for a pattern that cannot be emitted. Without it, the default logger of
`hecate.log` receives the warning, when that module is loaded.

`pattern` and `format` are not checked on a string that already has an `invalid_utf8` or `max_length` violation.

Without `max_length`, a string longer than 65536 bytes is not matched. It gets a `pattern` (or `format`) violation
with `context.reason = "too_long_for_pattern"`.

## Formats

`format` accepts the values of this table. Any other value is refused at declaration, with the list of accepted
formats.

The checks are conservative subsets of the standards: they may refuse a value that the standard allows.

| Format | Accepts | Standard |
|---|---|---|
| `uuid` | 8-4-4-4-12 hexadecimal digits with hyphens, either case | RFC 9562 (text form) |
| `date` | `YYYY-MM-DD`, a real calendar date (leap years included) | RFC 3339 `full-date` |
| `date-time` | a `date`, `T` or `t`, `hh:mm:ss`, optional fraction, then `Z`, `z` or `+hh:mm`/`-hh:mm`; a second of 60 is accepted | RFC 3339 `date-time` |
| `email` | one `@`, a non-empty local part, a dotted domain without empty labels; no whitespace or control character; at most 254 bytes | RFC 5321 (length) |
| `ipv4` | a dotted quad, each part 0 to 255, no leading zero | RFC 2673, section 3.2 |
| `uri` | a scheme followed by `:`, only unreserved, reserved and percent-encoded characters | RFC 3986 |

Other formats of JSON Schema (`hostname`, `ipv6`, `time`, `uri-reference`, ...) are not supported.

## Number options

`schema.integer` and `schema.number` take the same options.

| Option | Type | Emits | Violation code |
|---|---|---|---|
| `minimum` | number | `minimum` | `minimum` |
| `maximum` | number | `maximum` | `maximum` |
| `exclusive_minimum` | number | `exclusiveMinimum` | `exclusive_minimum` |
| `exclusive_maximum` | number | `exclusiveMaximum` | `exclusive_maximum` |
| `multiple_of` | whole number greater than 0 | `multipleOf` | `multiple_of` |

`multiple_of` refuses a fractional divisor such as `0.01`. Use one of two alternatives instead:

- integers in [minor units](glossary.md#types-and-validation), the smallest unit of a currency (cents);
- a `string` with a `pattern`, for a fixed number of decimals.

## Constants

| Constructor | Accepts | Emits | Violation code |
|---|---|---|---|
| `schema.literal(value)` | exactly `value` | `const` | `literal` |
| `schema.enumeration({ "a", "b" })` | one of the constants | `enum` | `enum` |
| `schema.enumeration(core_enumeration)` | the name of one member; `build` gives the member | `type: string`, `enum` | `enum` |

## Objects and maps

| Constructor | Options | Emits |
|---|---|---|
| `schema.object(properties, options?)` | `additional_properties` (boolean, default `false`) | `type: object`, `properties`, `required`, `additionalProperties` |
| `schema.map(value, options?)` | `min_properties`, `max_properties` (integers) | `type: object`, `additionalProperties: <value>`, `minProperties`, `maxProperties` |

Every property of an `object` is required unless it is wrapped (next table). A missing property is the violation
`required`. An undeclared property is the violation `additional_properties`.

A `map` has string keys that are not declared in advance. Every value has the schema `value`. There is no key
schema.

### Property wrappers

| Wrapper | Meaning | Emits |
|---|---|---|
| `schema.optional(inner)` | the property may be absent | the schema of `inner`; the property is not in `required` |
| `schema.nullable(inner)` | the value may also be `json.null` | `anyOf: [<inner>, { type: null }]` |
| `schema.default(inner, value)` | absent: `coerce` and `build` (not PATCH) supply a copy of `value` | the schema of `inner` with `default` |

## Arrays

`schema.array(item, options?)`:

| Option | Type | Emits | Violation code |
|---|---|---|---|
| `min_items` | integer | `minItems` | `min_items` |
| `max_items` | integer | `maxItems` | `max_items` |
| `unique_items` | boolean | `uniqueItems` | `unique_items` |
| `delimiter` | non-empty string, default `","` | nothing | none |

`delimiter` is how `coerce` splits a text (a query parameter, for example) into items.

The JSON Pointers of items are 0-based.

## Sum types

A [sum type](glossary.md#types-and-validation) is a value that is exactly one of several variants.

| Constructor | Meaning | Emits |
|---|---|---|
| `schema.union(alternatives)` | a value accepted by at least one alternative ([sum type](glossary.md#types-and-validation)) | `anyOf` |
| `schema.tagged_union(tag, variants)` | `variants` maps a name to an `object` schema; the property `tag` holds the name | `oneOf`, each variant with its tag as `const` |

A `union` refuses at declaration every alternative that accepts null. Write `schema.nullable(schema.union(...))`
instead.

Prefer `tagged_union` for objects that differ by a tag. It dispatches on the tag, and costs less.

## Names and classes

A [class-bound schema](glossary.md#types-and-validation) is the schema of a class, returned by its class-level
`schema()`. The class owns the schema name.

| Constructor | Meaning | Emits |
|---|---|---|
| `schema.of(Class)` | the schema of a class that implements `schema.Representable` ([class-bound schema](glossary.md#types-and-validation)) | `$ref` to `$defs/<class name>` |
| `schema.named(name, inner)` | an inline schema given a name | `$ref` to `$defs/<name>` |

Two different bodies under one name in one emission raise `ArgumentError`.

## Keywords that are never emitted

The emission covers these keywords:

- `type`, `enum`, `const`;
- the numeric, string, array and object keywords above;
- `properties`, `required`, `additionalProperties`, `items`;
- `anyOf`, `oneOf`, `default`, `format`;
- `$defs` and local `$ref`.

These JSON Schema keywords have no constructor:

- `allOf`, `not`, `if`, `then`, `else`;
- `contains`, `prefixItems`;
- `patternProperties`, `propertyNames`, `dependentSchemas`, `dependentRequired`;
- `unevaluatedProperties`, `unevaluatedItems`;
- `$id`, anchors, `$dynamicRef`, remote `$ref`;
- the `content` keywords.

A predicate written in Lua (`refine`) is not offered. JSON Schema could not express it, so the emitted contract would
be looser than the check.

## Violation codes

A [violation](glossary.md#types-and-validation) is one reason a value does not conform to a schema. `validate`
collects them all. Every violation has four fields:

- `path`, a JSON Pointer (RFC 6901) to the offending value;
- `code`, from the table below;
- `message`;
- `context`, a table of the fields listed below.

The codes are stable.

| Code | Context fields | Raised by |
|---|---|---|
| `type` | `expected`, `received` | every kind, for a value of another type |
| `required` | `property` | `object`; `tagged_union` without its tag |
| `additional_properties` | `property` | `object` |
| `minimum`, `maximum` | `minimum`, `maximum` | `integer`, `number` |
| `exclusive_minimum`, `exclusive_maximum` | `exclusive_minimum`, `exclusive_maximum` | `integer`, `number` |
| `multiple_of` | `multiple_of` | `integer`, `number` |
| `min_length`, `max_length` | `min_length`, `max_length` | `string` |
| `invalid_utf8` | none | `string` with a declared length |
| `pattern` | `pattern`, and `reason`, `max_bytes` | `string` |
| `format` | `format`, and `reason`, `max_bytes` | `string` |
| `literal` | `value` | `literal` |
| `enum` | `values` | `enumeration` |
| `min_items`, `max_items` | `min_items`, `max_items` | `array` |
| `unique_items` | `index` | `array` |
| `min_properties`, `max_properties` | `min_properties`, `max_properties` | `map` |
| `union` | `alternatives` | `union` |
| `tagged_union` | `tag`, `values` | `tagged_union`, for an unknown tag |
| `coercion` | `expected` | `coerce`, and `build` with `coerce = true` |
| `depth_limit` | `max_depth` | every container, beyond `json.DEFAULT_MAX_DEPTH` levels (1000 by default; `limits.max_depth` lowers it at boot) |
| `complexity_limit` | `max_steps` | a call that spends more than 1,000,000 steps |
| `too_many_violations` | `max` | a call that keeps 100 violations; it replaces the 101st |

`context.reason` of `pattern` and `format` takes one of two values:

- `too_long_for_pattern`, for a string longer than 65536 bytes without `max_length`;
- `malformed_pattern`, for a `pattern` that Lua gave up on.

## See also

- [Validate values with schemas](../how-to/validate-with-schemas.md)
- [Schemas and contracts](../explanation/schemas-and-contracts.md)
- The generated reference of [`hecate.schema`](schema/index.md)
