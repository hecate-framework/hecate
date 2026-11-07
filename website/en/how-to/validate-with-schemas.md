---
description: Declare schemas with hecate.schema, validate values with JSON Pointer error paths, and emit JSON Schema 2020-12.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Validate values with schemas

This guide shows how to declare a schema, validate a value against it and emit the matching JSON
Schema document with `hecate.schema`. It is written for hecate 0.x and Lua 5.5.

## Declare and validate

A schema is an immutable value built from constructors (`string`, `integer`, `object`, `array`,
`optional`, `union`, ...) with refinements as options. `validate` collects every violation; the
`path` of each one is an RFC 6901 JSON Pointer.

<!-- example: packages/schema/examples/hecate.schema.validate.lua -->
```lua
-- Declare a schema once, then validate a value: every violation is collected, each with the
-- JSON Pointer of the offending value.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, violations = user:validate({ name = "", age = -1 })
assert(violations)
print(("%s %d %s %s"):format(tostring(ok), #violations, violations[1].path, violations[2].path))
-- Prints: false 2 /age /name
```

`check(value)` returns the value or raises a `ValidationError` whose `context.violations` holds the
same list. Undeclared properties of an `object` are rejected unless `additional_properties` says
otherwise.

## Choose between `union` and `tagged_union`

When the alternatives of a sum differ by a property that holds a constant (a `type` or `kind`
field), declare a `tagged_union`: the validator reads the tag once and validates only the selected
variant, with no re-validation. A `union` decides each alternative in turn (stopping at the first
violation, literal properties first) and remembers its answer for each table of the content during
one call, so the work is proportional to the tables times the unions. As a backstop, a call that
needs more than 1,000,000 steps ends with a `complexity_limit` violation at the path where it
stopped. A failed
`union` reports the violations of its alternatives in `context.alternatives` only at the
outermost union.

## Name and reuse schemas

A class owns the name of its schema. Declare a class-level function `schema()` that returns the schema, and
use `schema.of(Class)` wherever the class is a part of another schema. The emission puts the body once in the
root `$defs` under the name of the class and uses a `$ref` at each use. Nothing else is declared, and classes
may refer to each other or to themselves.

A schema that has neither a class nor a call to `named` is inlined and never receives a name.

For a data transfer object that has no class, `schema.named("User", body)` is the explicit opt-in: it
validates and coerces like `body`, and the emission names it in the same way. A name is made of letters,
digits, `_`, `.` and `-`.

Two different bodies under one name in one emission raise an `ArgumentError` that names the colliding name
and says where each comes from: a class, or `named`. This covers an inline name equal to the name of a
class. Equal bodies share one definition.

## Emit JSON Schema

`to_json_schema()` returns a JSON Schema 2020-12 document as plain values.

<!-- example: packages/schema/examples/hecate.schema.to_json_schema.lua -->
```lua
-- The same schema emits a JSON Schema 2020-12 document, here to list its required properties.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string(),
  nickname = schema.optional(schema.string()),
})

local document = user:to_json_schema()
print(("%s %d"):format(document.type, #document.required))
-- Prints: object 1
```

## Defaults

`schema.default(inner, value)` makes a property optional. `coerce` (path, query and header texts)
and `build` (JSON content) give an absent property a fresh copy of the default, so no table is
shared between requests and the content you passed is never modified. `build` applies defaults for
POST and PUT but never for PATCH, where an absent attribute means unchanged. An explicit `null`
stays `null` and never takes the default. `schema.sent(instance, name)` stays false for an
attribute filled by a default, so an action can tell what the client really sent. `validate` never
supplies a value.

Choices taken conservatively (for example, `integer` refuses `1.0`) are listed in the package
README and in the open questions.
