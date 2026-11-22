-- Case folding of file names, for the comparison of names that a case-insensitive file system (macOS, Windows) treats as
-- one: `Ж.md` and `ж.md`, `Img/a.svg` and `img/a.svg`.
--
-- This is the *simple* case folding of the Unicode Standard (3.13, "Default Case Algorithms"; the statuses C and S of
-- `CaseFolding.txt`) for the code points of the scripts that file names use in practice: Basic Latin, Latin-1
-- Supplement, Latin Extended-A, the regular pairs of Latin Extended-B, Latin Extended Additional, Greek and Coptic,
-- Cyrillic and its Supplement, Armenian and the fullwidth Latin letters, plus the few singletons that fold to those
-- letters (the micro sign, the long s, the Kelvin, Ohm and Angstrom signs). The ranges are written by rule, not copied
-- from the data file, and are checked against it by the maintainer when Unicode is updated.
--
-- Not covered (a limit, recorded in docs/open-questions.md): Greek Extended (polytonic Greek, U+1F00 to U+1FFF),
-- Cherokee, Georgian, Glagolitic, Coptic, Deseret and the other cased scripts, the irregular letters of Latin
-- Extended-B and IPA Extensions, and the full folding of the status F (`ß` is not `ss`, as in a simple folding). Two
-- names that differ only by case in an uncovered script are not detected as colliding. The data belongs in
-- `hecate-unicode-data` (ADR 0032 leaves case folding out of its scope: a new ADR decides).
--
-- A name that is not valid UTF-8 is folded for the ASCII letters only (a file name is a sequence of bytes on Linux).
global <const> string, utf8, ipairs

local M = {}

-- { first, last, offset, step }: the code points first, first + step, ... up to last fold to the code point plus the
-- offset. `step` 2 is the "even letters are upper case, the next one is its lower case" layout of many blocks.
local RANGES = {
  { 0x41, 0x5A, 32, 1 }, -- Basic Latin
  { 0xB5, 0xB5, 0x3BC - 0xB5, 1 }, -- MICRO SIGN folds to GREEK SMALL LETTER MU
  { 0xC0, 0xD6, 32, 1 }, { 0xD8, 0xDE, 32, 1 }, -- Latin-1 Supplement (not the multiplication sign U+D7)
  { 0x100, 0x12E, 1, 2 }, { 0x132, 0x136, 1, 2 }, { 0x139, 0x147, 1, 2 }, { 0x14A, 0x176, 1, 2 }, -- Latin Extended-A
  { 0x178, 0x178, 0xFF - 0x178, 1 }, { 0x179, 0x17D, 1, 2 },
  { 0x17F, 0x17F, 0x73 - 0x17F, 1 }, -- LONG S folds to s
  { 0x1A0, 0x1A4, 1, 2 }, { 0x1CD, 0x1DB, 1, 2 }, { 0x1DE, 0x1EE, 1, 2 }, { 0x1F4, 0x1F4, 1, 1 }, { 0x1F8, 0x21E, 1, 2 }, -- Latin Extended-B
  { 0x222, 0x232, 1, 2 }, { 0x246, 0x24E, 1, 2 }, -- (regular pairs only; Romanian S and T with comma below are U+218 to U+21B)
  { 0x370, 0x372, 1, 2 }, { 0x376, 0x376, 1, 1 }, { 0x37F, 0x37F, 0x3F3 - 0x37F, 1 }, -- Greek and Coptic
  { 0x345, 0x345, 0x3B9 - 0x345, 1 }, -- COMBINING GREEK YPOGEGRAMMENI folds to iota
  { 0x386, 0x386, 0x3AC - 0x386, 1 }, { 0x388, 0x38A, 37, 1 }, { 0x38C, 0x38C, 0x3CC - 0x38C, 1 },
  { 0x38E, 0x38F, 63, 1 }, { 0x391, 0x3A1, 32, 1 }, { 0x3A3, 0x3AB, 32, 1 },
  { 0x3C2, 0x3C2, 1, 1 }, -- FINAL SIGMA folds to sigma
  { 0x3CF, 0x3CF, 0x3D7 - 0x3CF, 1 }, { 0x3D0, 0x3D0, 0x3B2 - 0x3D0, 1 }, { 0x3D1, 0x3D1, 0x3B8 - 0x3D1, 1 },
  { 0x3D5, 0x3D5, 0x3C6 - 0x3D5, 1 }, { 0x3D6, 0x3D6, 0x3C0 - 0x3D6, 1 }, { 0x3D8, 0x3EE, 1, 2 },
  { 0x3F0, 0x3F0, 0x3BA - 0x3F0, 1 }, { 0x3F1, 0x3F1, 0x3C1 - 0x3F1, 1 }, { 0x3F4, 0x3F4, 0x3B8 - 0x3F4, 1 },
  { 0x3F5, 0x3F5, 0x3B5 - 0x3F5, 1 }, { 0x3F7, 0x3F7, 1, 1 }, { 0x3F9, 0x3F9, 0x3F2 - 0x3F9, 1 },
  { 0x3FA, 0x3FA, 1, 1 }, { 0x3FD, 0x3FF, -130, 1 },
  { 0x400, 0x40F, 80, 1 }, { 0x410, 0x42F, 32, 1 }, -- Cyrillic
  { 0x460, 0x480, 1, 2 }, { 0x48A, 0x4BE, 1, 2 }, { 0x4C0, 0x4C0, 0x4CF - 0x4C0, 1 }, { 0x4C1, 0x4CD, 1, 2 },
  { 0x4D0, 0x52E, 1, 2 }, -- (through Cyrillic Supplement)
  { 0x531, 0x556, 48, 1 }, -- Armenian
  { 0x1E00, 0x1E94, 1, 2 }, { 0x1E9B, 0x1E9B, 0x1E61 - 0x1E9B, 1 }, { 0x1E9E, 0x1E9E, 0xDF - 0x1E9E, 1 },
  { 0x1EA0, 0x1EFE, 1, 2 }, -- Latin Extended Additional (Vietnamese)
  { 0x2126, 0x2126, 0x3C9 - 0x2126, 1 }, { 0x212A, 0x212A, 0x6B - 0x212A, 1 }, { 0x212B, 0x212B, 0xE5 - 0x212B, 1 },
  { 0xFF21, 0xFF3A, 32, 1 }, -- Halfwidth and Fullwidth Forms
}

local folding -- code point -> folded code point, built on first use

local function build()
  folding = {}
  for _, range in ipairs(RANGES) do
    for code = range[1], range[2], range[4] do folding[code] = code + range[3] end
  end
end

--- Folds the letters of `text` to their simple case folding (see the header for the scripts covered).
---@param text string
---@return string
function M.fold(text)
  if not folding then build() end
  if not utf8.len(text) then
    return (text:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end))
  end
  return (text:gsub(utf8.charpattern, function(character)
    local folded = folding[utf8.codepoint(character)]
    return folded and utf8.char(folded) or nil
  end))
end

--- The covered ranges, for the tests and for the check against the Unicode data.
---@return table[]
function M.ranges() return RANGES end

return M
