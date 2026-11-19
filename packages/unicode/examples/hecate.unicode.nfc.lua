-- "café" typed with a letter and a combining accent, and "café" with one
-- precomposed letter, are two byte strings. In Normalization Form C they are
-- one, so they can be compared, stored and used as keys.
local unicode = require("hecate.unicode")

local typed = "cafe\u{301}"
local stored = "caf\u{E9}"
print(("%s %s"):format(typed == stored, unicode.nfc(typed) == unicode.nfc(stored)))
-- Prints: false true
