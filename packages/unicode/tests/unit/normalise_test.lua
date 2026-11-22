local test = require("harness.test")
local unicode = require("hecate.unicode")
local T = test.Case("NormaliseTest")

local function u(...) return utf8.char(...) end

function T:test_ascii_and_the_empty_string_are_returned_as_they_are()
  for _, text in ipairs({ "", "plain", "guide/a-b_c.md", "\0\1\127" }) do
    self:assert_equal(text, unicode.nfc(text))
    self:assert_equal(text, unicode.nfd(text))
  end
end

function T:test_nfc_composes_and_nfd_decomposes_the_latin_letters()
  self:assert_equal(u(0xE9), unicode.nfc(u(0x65, 0x301)))
  self:assert_equal(u(0x65, 0x301), unicode.nfd(u(0xE9)))
  self:assert_equal("caf\u{E9}/\u{C5}ngstr\u{F6}m", unicode.nfc("cafe\u{301}/A\u{30A}ngstro\u{308}m"))
  self:assert_equal("cafe\u{301}", unicode.nfd("caf\u{E9}"))
end

function T:test_vietnamese_letters_with_two_marks_whatever_the_order_of_the_marks()
  self:assert_equal(u(0x1EAD), unicode.nfc(u(0x61, 0x323, 0x302)))
  self:assert_equal(u(0x1EAD), unicode.nfc(u(0x61, 0x302, 0x323)))
  self:assert_equal(u(0x1EA5), unicode.nfc(u(0x61, 0x302, 0x301)))
  self:assert_equal(u(0x61, 0x323, 0x302), unicode.nfd(u(0x1EAD)))
end

function T:test_romanian_letters_with_comma_below()
  self:assert_equal(u(0x219), unicode.nfc(u(0x73, 0x326)))
  self:assert_equal(u(0x21B), unicode.nfc(u(0x74, 0x326)))
  self:assert_equal(u(0x73, 0x326), unicode.nfd(u(0x219)))
end

function T:test_singletons_are_replaced_in_both_forms()
  self:assert_equal(u(0xC5), unicode.nfc(u(0x212B)), "ANGSTROM SIGN")
  self:assert_equal(u(0x3A9), unicode.nfc(u(0x2126)), "OHM SIGN")
  self:assert_equal(u(0x41, 0x30A), unicode.nfd(u(0x212B)))
  self:assert_equal(u(0x3AC), unicode.nfc(u(0x1F71)), "GREEK SMALL LETTER ALPHA WITH OXIA")
  self:assert_equal(u(0x3B1, 0x301), unicode.nfd(u(0x1F71)))
end

function T:test_greek_with_tonos_and_dialytika()
  self:assert_equal(u(0x3AC), unicode.nfc(u(0x3B1, 0x301)))
  self:assert_equal(u(0x390), unicode.nfc(u(0x3B9, 0x308, 0x301)))
  self:assert_equal(u(0x3B9, 0x308, 0x301), unicode.nfd(u(0x390)))
end

function T:test_cyrillic()
  self:assert_equal(u(0x439), unicode.nfc(u(0x438, 0x306)))
  self:assert_equal(u(0x451), unicode.nfc(u(0x435, 0x308)))
  self:assert_equal(u(0x438, 0x306), unicode.nfd(u(0x439)))
end

function T:test_hangul_syllables_are_composed_and_decomposed_by_arithmetic()
  self:assert_equal(u(0xAC01), unicode.nfc(u(0x1100, 0x1161, 0x11A8)), "LVT")
  self:assert_equal(u(0xAC00), unicode.nfc(u(0x1100, 0x1161)), "LV")
  self:assert_equal(u(0xAC01), unicode.nfc(u(0xAC00, 0x11A8)), "LV plus T")
  self:assert_equal(u(0xD55C), unicode.nfc(u(0x1112, 0x1161, 0x11AB)))
  self:assert_equal(u(0x1100, 0x1161, 0x11A8), unicode.nfd(u(0xAC01)))
  self:assert_equal(u(0x1100, 0x1161), unicode.nfd(u(0xAC00)))
  self:assert_equal(u(0xD7A3), unicode.nfc(unicode.nfd(u(0xD7A3))), "the last syllable")
  self:assert_equal(u(0x1100, 0x1100), unicode.nfc(u(0x1100, 0x1100)), "L plus L stays")
  self:assert_equal(u(0xAC01, 0x11A8), unicode.nfc(u(0xAC01, 0x11A8)), "LVT plus T stays")
end

function T:test_combining_marks_are_reordered_by_class()
  -- U+0301 has class 230 and U+0323 class 220: canonical order puts the lower class first.
  self:assert_equal(u(0x61, 0x323, 0x301), unicode.nfd(u(0x61, 0x301, 0x323)))
  self:assert_equal(u(0x1EA1, 0x301), unicode.nfc(u(0x61, 0x301, 0x323)))
  -- Marks of the same class keep their order (the sort is stable).
  self:assert_equal(u(0x78, 0x301, 0x307), unicode.nfd(u(0x78, 0x301, 0x307)))
  self:assert_equal(u(0x78, 0x307, 0x301), unicode.nfd(u(0x78, 0x307, 0x301)))
  -- A mark with class 0 ends the run.
  self:assert_equal(u(0x61, 0x301, 0x62, 0x323), unicode.nfd(u(0x61, 0x301, 0x62, 0x323)))
end

function T:test_a_blocked_mark_is_not_composed()
  -- i + U+0307 has no composite, so U+0301 (same class) is blocked and does not compose with i.
  self:assert_equal(u(0x69, 0x307, 0x301), unicode.nfc(u(0x69, 0x307, 0x301)))
  -- With a lower class in between, it is not blocked.
  self:assert_equal(u(0x1ECB, 0x301), unicode.nfc(u(0x69, 0x301, 0x323)))
end

function T:test_a_lone_mark_and_unassigned_code_points_pass_through()
  self:assert_equal(u(0x301), unicode.nfc(u(0x301)))
  self:assert_equal(u(0x301, 0x61), unicode.nfc(u(0x301, 0x61)))
  self:assert_equal("x" .. u(0x301), unicode.nfc("x" .. u(0x301)))
  self:assert_equal(u(0x378, 0x301), unicode.nfc(u(0x378, 0x301)), "U+0378 is unassigned")
  self:assert_equal(u(0x10FFFF), unicode.nfc(u(0x10FFFF)))
  self:assert_equal(u(0x4E2D, 0x6587), unicode.nfc(u(0x4E2D, 0x6587)))
end

function T:test_normalisation_is_idempotent_and_nfc_of_nfd_is_nfc()
  for _, text in ipairs({ u(0x1EAD, 0x1F71, 0xAC01, 0x212B), u(0x61, 0x301, 0x323, 0x302), "a/b" .. u(0x65, 0x301) }) do
    self:assert_equal(unicode.nfc(text), unicode.nfc(unicode.nfc(text)))
    self:assert_equal(unicode.nfd(text), unicode.nfd(unicode.nfd(text)))
    self:assert_equal(unicode.nfc(text), unicode.nfc(unicode.nfd(text)))
    self:assert_equal(unicode.nfd(text), unicode.nfd(unicode.nfc(text)))
  end
end

function T:test_is_nfc_and_is_nfd()
  self:assert_true(unicode.is_nfc("plain"))
  self:assert_true(unicode.is_nfc(u(0xE9)))
  self:assert_false(unicode.is_nfc(u(0x65, 0x301)))
  self:assert_true(unicode.is_nfd(u(0x65, 0x301)))
  self:assert_false(unicode.is_nfd(u(0xE9)))
  self:assert_true(unicode.is_nfc("") and unicode.is_nfd(""))
end

function T:test_the_unicode_version_in_use_is_reported()
  self:assert_equal("string", type(unicode.version))
  self:assert_true(unicode.version:match("^%d+%.%d+%.%d+$") ~= nil)
  self:assert_equal(require("hecate.unicode_data").unicode_version, unicode.version)
end

function T:test_long_inputs_do_not_overflow_the_stack_and_stay_fast()
  self:assert_equal(("\u{E9}"):rep(300000), unicode.nfc(("e\u{301}"):rep(300000)))
  -- A long run of marks in the wrong order: sorted in n log n, not n squared.
  local run = ("\u{301}\u{323}"):rep(50000)
  local sorted = unicode.nfd("a" .. run)
  self:assert_equal("a" .. ("\u{323}"):rep(50000) .. ("\u{301}"):rep(50000), sorted)
end

return T
