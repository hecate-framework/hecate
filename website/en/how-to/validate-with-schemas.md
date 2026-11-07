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

Choices taken conservatively (for example, `integer` refuses `1.0`) are listed in the package
README and in the open questions.
