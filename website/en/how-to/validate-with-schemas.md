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
