-- Normalization Form D splits a letter into its base and its marks. A Hangul
-- syllable becomes its conjoining jamo, computed and not looked up.
local unicode = require("hecate.unicode")

local syllable = "\u{AC01}"
print(("%d %d"):format(utf8.len(syllable), utf8.len(unicode.nfd(syllable))))
-- Prints: 1 3
