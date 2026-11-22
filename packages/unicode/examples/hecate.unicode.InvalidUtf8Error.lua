-- A string that is not well-formed UTF-8 raises an error object of the Hecate
-- hierarchy; `context.position` is the 1-based byte of the first invalid byte.
local unicode = require("hecate.unicode")

local ok, err = pcall(unicode.nfc, "caf\xE9")
---@cast err any
print(("%s %s %d"):format(ok, err.code, err.context.position))
-- Prints: false hecate.unicode.InvalidUtf8Error 4
