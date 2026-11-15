-- Check a property over values generated from a schema. A failing property
-- is shrunk to a small counterexample that still conforms to the schema.
local schema = require("hecate.schema")
local test = require("hecate.test")

local age = schema.integer({ minimum = 0, maximum = 120 })

-- A property fails by returning false (or by raising).
local ok = test.check_property(age, function(n) return n >= 0 end)
print(ok.ok, ok.runs)
-- Prints: true	100

-- The seed makes the run reproducible; the counterexample is the smallest
-- failing value the shrinking reached.
local result = test.check_property(age, function(n) return n < 18 end,
  { seed = 7 })
print(result.ok, result.counterexample)
-- Prints: false	18

-- Values that break the schema in exactly one place, with the violation.
local value, expected = test.generate_invalid(age, 1)
print(age:validate(value), expected.code)
-- Prints: false	maximum
