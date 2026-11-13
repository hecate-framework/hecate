-- A map has string keys that are not declared in advance, and one schema for
-- every value.
local schema = require("hecate.schema")

local stock = schema.map(schema.integer({ minimum = 0 }), { max_properties = 2 })

print((stock:validate({ apples = 3, pears = 0 })))
-- Prints: true

local _, violations = stock:validate({ apples = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /apples	minimum

_, violations = stock:validate({ apples = 1, pears = 2, plums = 3 })
violation = assert(violations)[1]
print(violation.path == "", violation.code)
-- Prints: true	max_properties

-- The emission is an object whose `additionalProperties` is the schema of the
-- values.
print(stock:to_json_schema().additionalProperties.type)
-- Prints: integer
