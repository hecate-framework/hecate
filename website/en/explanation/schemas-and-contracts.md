---
description: Why hecate.schema describes types as runtime data, how validation, coercion and build differ, what the presence set records, and the bounds and limits to know.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Schemas and contracts

This page explains how `hecate.schema` models types and why. It is written for hecate 0.x and Lua 5.5.
For recipes, see [Validate values with schemas](../how-to/validate-with-schemas.md). The full
specification is [schemas-and-contracts.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md)
in the repository, and the code reference is [`hecate.schema`](../reference/schema/index.md).

## Schemas are runtime data

A [schema](../reference/glossary.md#types-and-validation) is an ordinary, immutable Lua value. It is
not a comment, a code generator input or a type that exists only at compile time. Lua has no static
types to read, so the declaration itself is the type.

This is what makes hecate contract-first. One value drives every use of a type:

- validation of decoded content,
- coercion of the texts of a path, a query string or a header,
- the instances an action receives,
- the JSON Schema 2020-12 document of the contract.

The contract cannot drift from the code, because there is no second description to keep in step. Each
schema compiles once, at declaration, into closures. A request does not walk the description.

The vocabulary is that of the literature. A base type restricted by predicates is a
refinement type (`integer` with `minimum = 1`). A record is a product type (`object`). A value that is exactly
one of several variants is a sum type (`union`, `tagged_union`). The members of an `object` are
properties, the JSON Schema term. The glossary defines each term.

## Validation, coercion and build

Three operations read a value against a schema. They answer different questions.

| Operation | Input | Answer |
|---|---|---|
| `validate` | decoded JSON content | does the value conform? Changes nothing |
| `coerce` | the texts of a path, query or header | the typed value, with defaults supplied |
| `build` | decoded JSON content, or texts with `coerce = true` | an instance of the class of each part |

`validate` is pure. It returns every violation, each with a JSON Pointer path, a code and a message,
so a client sees all its mistakes at once. It never converts and never supplies a value. `integer` refuses
`1.0` and a text such as `"42"`.

Coercion exists because texts are not JSON. A query value is always a string, and the schema knows the
type it should have. The rules are strict: `integer` reads an optional minus sign and digits, `boolean`
reads `true` and `false` only, and a text is never converted to null. JSON content is not coerced,
because JSON already carries types, and a string where a number is expected is a mistake to report.

`build` validates first, then makes the instances. A part declared with `schema.of(Class)` becomes an
instance of that class, without calling its `init`, because validation has already guaranteed that the
attributes conform. With `coerce = true`, `build` converts texts first and then builds, so a class such as
a list filter is built from a query string in one call.

The response goes the other way. `represent` passes an instance through its schema and returns plain
values: the attributes the schema declares (an undeclared one never leaks), enumeration members as their
names, nested parts, arrays, maps and unions converted recursively. The kernel then encodes that plain result
with `json.encode`, so an instance goes to plain values, then to JSON, and `hecate.json` stays unaware of
classes. `represent` does not validate, since a response that does not conform is a bug of the server, and it
is bounded by the same depth guard and work budget as the other operations, so a cycle in the object graph
ends with a `depth_limit` error.

## The presence set and PATCH

A POST or a PUT carries a whole resource. An absent attribute is `nil`, and validation fails only when the
attribute is required. A PATCH carries part of a resource, so two different statements look the same in
the instance:

- an attribute that is absent means unchanged,
- an attribute that is an explicit `null` means cleared.

Both are `nil` in the instance. Hecate keeps the difference in a presence set, read with
`schema.sent(instance, name)`. The set lives in a side table with weak keys, outside the instance. So the
instance holds only its attributes: `pairs` and `json.encode` see nothing else, and an instance that was
not built by `build` simply has sent nothing.

The alternative would be to store `json.null` as the value of a cleared attribute. It was rejected,
because every reader of the attribute would then have to test for a sentinel.

A PATCH relaxes the required properties of the top-level object only. A nested object is replaced as a
whole, not merged, so it stays strict. Defaults never apply to a PATCH, because a default would turn an
unchanged attribute into a changed one. In the other methods, `sent` stays false for an attribute filled by a
default, so an action can tell what the client really sent.

## Why classes own schema names

An API contract has components with names. Someone has to own the names. In hecate the class does. A class
declares a class-level `schema()` and an interface can require it. Another schema or a route names the
class itself with `schema.of(Class)`, never a string.

This gives one place for each name and one function for each type. Validation, coercion, build and
emission all call the same function, and the result is cached because it is immutable. The emission
writes each class once in `$defs` and refers to it. Recursive types work because the resolution is lazy,
and a cycle closes with a `$ref`.

A schema without a class is inlined and never named. `named` is the explicit opt-in for a data transfer
object that has no class. Two different bodies under one name are an error, not a silent merge, so a
contract never changes meaning because of the order of declarations.

## Safety bounds

Schemas validate untrusted content, so every call is bounded.

- **Depth.** Nesting is limited to 1000 levels, the same maximum as `json.decode` and `json.encode`. The
  decoder refuses deeper content before `schema` sees it. A hand-built table can still be deeper, and
  then a `depth_limit` violation stops the call at the path where it was reached, instead of
  exhausting the stack.
- **Work budget.** One call spends at most 1,000,000 steps, one per container visited or alternative
  tried. Beyond it, the call ends with a `complexity_limit` violation. The budget is a backstop. The
  other guards keep ordinary schemas far below it.
- **Fail-fast unions.** A `union` decides each alternative at its first violation, literal properties
  first, and remembers its answer per table during one call. Without this, a recursive union of containers
  costs exponential time in its depth.
- **`tagged_union`.** When variants differ by a constant property, prefer it to a `union`. It reads the
  tag once, validates one variant and reports that variant's violations. It is the cheapest sum and also
  the clearest error.

## Limits to know

Some differences between Lua and JSON Schema cannot be removed. Hecate documents them instead of hiding
them, and it never approximates silently.

- **Lua patterns and ECMA-262.** `pattern` is a Lua pattern, not a regular expression. The emission
  translates a defined ASCII subset exactly and refuses the rest (`%b`, `%f`, non-ASCII bytes). Lua
  matches bytes and ECMA-262 matches UTF-16 code units, so `.` and negated sets can disagree on non-ASCII
  input. For ASCII input the two agree.
- **Bytes and code points.** `min_length` and `max_length` count code points, as JSON Schema does, and
  a string that is not well-formed UTF-8 is a violation. `pattern` matches bytes.
- **`1.0` and integer.** `integer` accepts only Lua integers. JSON Schema cannot tell `1` from `1.0`, so
  the emitted `integer`, `const` and `enum` also accept `1.0`. This is the one documented gap between
  validator and contract, pinned by a test.
- **Binary floats and `multiple_of`.** Binary floats cannot express a decimal step: the remainder of
  `19.99` by `0.01` is not zero. `multiple_of` therefore takes whole-number divisors only. For decimal
  places, use integers in minor units or a string with a pattern.
- **Unsupported constructs.** A construct that JSON Schema cannot express exactly is not allowed.

## Related reading

- [Validate values with schemas](../how-to/validate-with-schemas.md), the recipes.
- [Encode and decode JSON](../how-to/encode-and-decode-json.md), the codec that shares the depth limit.
- The [glossary](../reference/glossary.md).
