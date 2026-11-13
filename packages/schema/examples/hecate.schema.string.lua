-- `format` checks well-known string formats. `pattern` is a Lua pattern,
-- translated to an ECMA-262 regular expression when the schema is emitted.
local schema = require("hecate.schema")

print((schema.string({ format = "email" }):validate("ada@example.org")))
-- Prints: true

local sku = schema.string({ pattern = "^%u%u%-%d+$" })
print((sku:validate("AB-42")), (sku:validate("ab-42")))
-- Prints: true	false
print(sku:to_json_schema().pattern)
-- Prints: ^[A-Z][A-Z]-[0-9]+$

-- A pattern that cannot be translated exactly is refused when emitting, never
-- approximated: `%b` and `%f`, and any non-ASCII byte.
for _, pattern in ipairs({ "%bxy", "%f[%w]", "caf\u{e9}" }) do
  local refused = schema.string({ pattern = pattern })
  print((pcall(refused.to_json_schema, refused)))
end
-- Prints: false
-- false
-- false

-- A `logger` reports the pattern at declaration instead.
schema.string({ pattern = "%bxy", logger = { warning = function(_, message) print(message) end } })
-- Prints: schema: pattern "%bxy" cannot be emitted: %b has no exact translation
