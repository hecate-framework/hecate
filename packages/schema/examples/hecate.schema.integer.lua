-- `multiple_of` takes a whole-number divisor. For decimal places, use minor
-- units or a string.
local schema = require("hecate.schema")

local lots = schema.integer({ multiple_of = 5 })
print((lots:validate(15)), (lots:validate(16)))
-- Prints: true	false

-- A fractional divisor is refused at declaration: binary floats cannot
-- express a decimal step.
local declared, err = pcall(schema.number, { multiple_of = 0.01 })
print(declared, tostring(err):match("ArgumentError: ([^;]+)"))
-- Prints: false	schema: number: option multiple_of must be a whole number

-- First alternative: an integer in minor units, here cents (1999 is 19.99).
local cents = schema.integer({ minimum = 0 })
print((cents:validate(1999)))
-- Prints: true

-- Second alternative: a string with exactly two decimals.
local price = schema.string({ pattern = "^%d+%.%d%d$" })
print((price:validate("19.99")), (price:validate("19.9")))
-- Prints: true	false
