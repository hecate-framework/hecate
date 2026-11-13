-- A union never accepts null on its own: `nullable` is the only way for a
-- property to accept null.
local json = require("hecate.json")
local schema = require("hecate.schema")

local plain = schema.union({ schema.string(), schema.integer() })
print((plain:validate(json.null)))
-- Prints: false

-- A `null` or `nullable` alternative is refused at declaration, with a hint.
local ok, err = pcall(schema.union, { schema.string(), schema.null() })
print(ok, (err --[[@as table]]).code)
-- Prints: false	hecate.core.ArgumentError

-- Wrap the union instead.
local identifier = schema.nullable(plain)
print((identifier:validate(json.null)), (identifier:validate("a1")), (identifier:validate(true)))
-- Prints: true	true	false

-- `any` is different: it accepts every value, null included, by an explicit
-- choice.
print((schema.union({ schema.string(), schema.any() }):validate(json.null)))
-- Prints: true
