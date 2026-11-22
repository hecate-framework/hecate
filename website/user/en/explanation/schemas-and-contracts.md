---
description: Why hecate.schema describes types as runtime data, how validation, coercion and build differ, what the presence set records, and the bounds and limits to know.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Schemas and contracts

This page explains how `hecate.schema` models types, and why. It is written for hecate 0.x and Lua 5.5.

For recipes, see [Validate values with schemas](../how-to/validate-with-schemas.md). The full specification is
[schemas-and-contracts.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md)
in the repository, and the code reference is [`hecate.schema`](../reference/schema/index.md).

## Schemas are runtime data

A [schema](../reference/glossary.md#types-and-validation) is the declaration of a type. In hecate it is an ordinary,
immutable Lua value. It is not a comment, an input of a code generator, or a type that exists only at compile time.
Lua has no static types to read, so the declaration itself is the type.

This is what makes hecate contract-first. One value drives every use of a type:

- the validation of decoded content;
- the coercion of the texts of a path, a query string or the header fields;
- the instances an action receives;
- the JSON Schema 2020-12 document of the contract.

The contract cannot drift from the code, because there is no second description to keep in step.

Each schema compiles once, at declaration, into closures. A request does not walk the description.

## The vocabulary of types

The vocabulary is that of the literature. The [glossary](../reference/glossary.md#types-and-validation) defines each
term.

| Term | Meaning | In `hecate.schema` |
|---|---|---|
| refinement type | a base type restricted by predicates | `integer` with `minimum = 1` |
| product type | a record of named components | `object` |
| sum type | a value that is exactly one of several variants | `union`, `tagged_union` |

The members of an `object` are properties, the JSON Schema term.

## Validation, coercion and build

Three operations read a value against a schema. They answer different questions.

| Operation | Input | Answer |
|---|---|---|
| `validate` | decoded JSON content | does the value conform? Changes nothing |
| `coerce` | the texts of a path, query or header fields | the typed value, with defaults supplied |
| `build` | decoded JSON content, or texts with `coerce = true` | an instance of the class of each part |

The same schema gives different answers to `validate` and to `coerce`:

```lua
local schema = require("hecate.schema")

local count = schema.integer({ minimum = 0 })
print((count:validate(42)), (count:validate("42")), (count:validate(1.0)))
-- Prints: true	false	false
print(count:coerce("42"))
-- Prints: true	42
```

### Validation

`validate` is pure. It returns every [violation](../reference/glossary.md#types-and-validation), each with a JSON
Pointer path, a code and a message. A client therefore sees all its mistakes at once.

`validate` never converts and never supplies a value. `integer` refuses `1.0` and a text such as `"42"`.

### Coercion

[Coercion](../reference/glossary.md#types-and-validation), the conversion of a text to a typed value, exists because
texts are not JSON. A query value is always a string, and the schema knows the type it should have.

The rules are strict:

- `integer` reads an optional minus sign and digits.
- `boolean` reads `true` and `false` only.
- `nullable` never converts a text to null. Only a constant null, such as `schema.literal(json.null)`, reads the text
  `null`.

JSON content is not coerced, because JSON already carries types. A string where a number is expected is a mistake to
report.

### Build

[`build`](../reference/glossary.md#types-and-validation) validates first, then makes the instances. A part declared
with `schema.of(Class)` becomes an instance of that class. Its `init` is not called, because validation has already
guaranteed that the attributes conform.

With `coerce = true`, `build` converts texts first and then builds. A class such as a list filter is then built from
a query string in one call.

### Representation

The response goes the other way. [`represent`](../reference/glossary.md#types-and-validation) passes an instance
through its schema and returns plain values, its
[representation](../reference/glossary.md#types-and-validation):

- the attributes the schema declares, and only those: an undeclared one never leaks;
- enumeration members as their names;
- nested parts, arrays, maps and unions, converted recursively.

The kernel then encodes that plain result with `json.encode`. An instance goes to plain values, then to JSON, and
`hecate.json` stays unaware of classes.

`represent` does not validate, since a response that does not conform is a bug of the server. It is bounded by the
same depth guard and work budget as the other operations, so a cycle in the object graph ends with a `depth_limit`
error.

An attribute that was sent as `null` is represented as `null`. Decode, build, represent and encode then give back the
same content.

## The presence set and PATCH

A POST or a PUT carries a whole resource. An absent attribute is `nil`, and validation fails only when the attribute
is required.

A PATCH carries part of a resource, so two different statements look the same in the instance:

- an attribute that is absent means unchanged;
- an attribute that is an explicit `null` means cleared.

Both are `nil` in the instance. hecate keeps the difference in a
[presence set](../reference/glossary.md#types-and-validation): the names of the attributes that were present in the
content, explicit `null` included. Read it with `schema.sent(instance, name)`.

The set lives in a side table with weak keys, outside the instance. The instance holds only its attributes: `pairs`
and `json.encode` see nothing else. An instance that was not built by `build` simply has sent nothing.

The alternative would be to store `json.null` as the value of a cleared attribute. It was rejected, because every
reader of the attribute would then have to test for a sentinel.

A PATCH relaxes the required properties of the top-level object only. A nested object is replaced as a whole, not
merged, so it stays strict.

Defaults never apply to a PATCH, because a default would turn an unchanged attribute into a changed one. In the other
methods, `sent` stays false for an attribute filled by a default, so an action can tell what the client really sent.

## Why classes own schema names

An API contract has components with names, and someone has to own the names. In hecate, the class does: its schema is
a [class-bound schema](../reference/glossary.md#types-and-validation).

A class declares a class-level `schema()`. The [interface](../reference/glossary.md#object-model-and-architecture)
`schema.Representable` requires it, and `schema.of` refuses a class that does not declare that interface. Another
schema or a route names the class itself with `schema.of(Class)`, never a string.

This gives one place for each name and one function for each type. Validation, coercion, build and emission all call
the same function, and the result is cached because it is immutable.

The emission writes each class once in `$defs` and refers to it. Recursive types work because the resolution is lazy,
and a cycle closes with a `$ref`.

A schema without a class is inlined and never named. `named` is the explicit opt-in for an inline schema that has no
class. Two different definitions under one name are an error, not a silent merge, so a contract never changes meaning
because of the order of declarations.

## Safety bounds

Schemas validate untrusted content, so every call is bounded.

- **Depth.** Nesting is limited to 1000 levels, the same maximum as `json.decode` and `json.encode`. The configuration
  key `limits.max_depth` can lower both at boot, never raise them. The decoder refuses deeper content before `schema`
  sees it. A hand-built table can still be deeper. A `depth_limit` violation then stops the call at the path where it
  was reached, instead of exhausting the stack.
- **Work budget.** One call spends at most 1,000,000 steps, one per container visited or alternative tried: this is its
  [work budget](../reference/glossary.md#types-and-validation). Beyond it, the call ends with a `complexity_limit`
  violation. The budget is a backstop: the other guards keep ordinary schemas far below it.
- **Fail-fast unions.** A `union` decides each alternative in
  [fail-fast mode](../reference/glossary.md#types-and-validation), at its first violation, literal properties first.
  It remembers its answer per table during one call. Without this, a recursive union of containers costs exponential
  time in its depth.
- **`tagged_union`.** When variants differ by a constant property, prefer it to a `union`. It reads the tag once,
  validates one variant and reports that variant's violations. It is the cheapest sum and also the clearest error.

## Limits to know

Some differences between Lua and JSON Schema cannot be removed. hecate documents them instead of hiding them, and it
never approximates silently.

### Lua patterns and ECMA-262

`pattern` is a Lua pattern, not a regular expression. The emission translates a defined ASCII subset exactly, and
refuses the rest: `%b`, `%f`, the position capture `()`, non-ASCII bytes, and a complemented class inside a set
(`[%W]`), among others.

Lua matches bytes, and ECMA-262 matches UTF-16 code units. So `.`, negated sets and negated classes can disagree on
non-ASCII input. For ASCII input the two agree.

Lua patterns can also backtrack, so patterns should be anchored. A string longer than 65536 bytes without a
`max_length` is never matched: it gets a `pattern` violation with `context.reason` set to `too_long_for_pattern`.

### Bytes and code points

`min_length` and `max_length` count code points, as JSON Schema does, and a string that is not well-formed UTF-8 is a
violation. `pattern` matches bytes.

### Deep hand-built tables

The structural equality of `unique_items` stops at the depth guard (1,000 levels). Two tables still different below
it are treated as different, never by a stack overflow. Decoded content cannot reach that depth.

### `1.0` and integer

`integer` accepts only Lua integers. JSON Schema cannot tell `1` from `1.0`, so the emitted `integer`, `const` and
`enum` also accept `1.0`. This is the one documented gap between validator and contract, pinned by a test.

### Binary floats and `multiple_of`

Binary floats cannot express a decimal step: the remainder of `19.99` by `0.01` is not zero. `multiple_of` therefore
takes whole-number divisors only. For decimal places, use integers in
[minor units](../reference/glossary.md#types-and-validation) or a string with a pattern.

### Per-call state

The validators, coercers, builders and representers keep their counters and caches in module-level state. Each public
call resets that state at its start.

A metamethod of a user object (an `__index` or `__pairs`) that yields during a call could interleave two calls
running in different coroutines. Such metamethods must not suspend.

### Null and unions

A union must not contain null: `nullable` is the only way for a property to accept null. `union` therefore refuses at
declaration every alternative that accepts null, and asks for `nullable(union(...))`. The refusal is an
`ArgumentError`, not a violation. It covers `null`, `nullable`, a literal null and an enumeration containing null.

`any` is not refused: it accepts every value by an explicit choice.

### Unsupported constructs

A construct that JSON Schema cannot express exactly is not allowed.

The emission covers `type`, `enum`, `const`, the numeric, string, array and object refinements, `properties`,
`required`, `additionalProperties`, `items`, `anyOf`, `oneOf`, `default`, `format`, `$defs` and local `$ref`. `oneOf`
is emitted only by `tagged_union`: a `union` is `anyOf`.

These keywords are not emitted, as a deliberate limit: `allOf`, `not`, `if`, `then` and `else`, `contains`,
`prefixItems`, `patternProperties`, `propertyNames`, `dependentSchemas`, `dependentRequired`,
`unevaluatedProperties`, `unevaluatedItems`, `$id`, anchors, `$dynamicRef`, remote `$ref` and the `content`
keywords. They are out of scope until a consumer needs them.

`refine`, a custom predicate, is not offered. A predicate cannot be emitted as JSON Schema, so the emitted contract
would be looser than the validator.

### Planned, not implemented

The generators of sample values (`generate`, `generate_invalid`, carried by the `test` package) do not exist yet.
Neither does the generation of `---@meta` files for LuaLS (carried by `doc` or `cli`).

## Related reading

- [Validate values with schemas](../how-to/validate-with-schemas.md), the recipes.
- [Schema keywords and formats](../reference/schema-keywords-and-formats.md), every constructor, option and code.
- [Encode and decode JSON](../how-to/encode-and-decode-json.md), the codec that shares the depth limit.
- The [glossary](../reference/glossary.md).
