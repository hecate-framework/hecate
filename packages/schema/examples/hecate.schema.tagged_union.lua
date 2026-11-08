-- A tagged union reads the tag once and validates only the selected variant.
local schema = require("hecate.schema")

local shape = schema.tagged_union("kind", {
  circle = schema.object({ radius = schema.number({ exclusive_minimum = 0 }) }),
  rectangle = schema.object({ width = schema.number(), height = schema.number() }),
})

print((shape:validate({ kind = "circle", radius = 2 })))

-- The violations are those of the selected variant, at the path of the offending value.
local _, violations = shape:validate({ kind = "circle", radius = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)

-- An unknown tag lists the variants; a missing tag is a missing property.
_, violations = shape:validate({ kind = "triangle" })
violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
_, violations = shape:validate({ radius = 2 })
violation = assert(violations)[1]
print(violation.path, violation.code)

-- The emission is a `oneOf` of the variants, each with the tag as a constant.
print(#shape:to_json_schema().oneOf)
-- Prints: true
-- /radius	exclusive_minimum
-- /kind	tagged_union	circle rectangle
-- /kind	required
-- 2
