---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local hangul = require("hecate.unicode.internal.hangul")
local T = test.Case("HangulTest")

-- Unicode Standard 3.12, "Conjoining Jamo Behavior": the arithmetic of the 11172 precomposed syllables.
function T:test_the_block_is_exactly_the_syllables()
  self:assert_equal(11172, hangul.SCOUNT)
  self:assert_true(hangul.is_syllable(0xAC00) and hangul.is_syllable(0xD7A3))
  self:assert_false(hangul.is_syllable(0xABFF) or hangul.is_syllable(0xD7A4))
end

function T:test_decomposition_of_known_syllables()
  self:assert_equal(0x1100, select(1, hangul.decompose(0xAC00)))
  local l, v, t = hangul.decompose(0xAC00)
  self:assert_equal(0x1161, v)
  self:assert_nil(t)
  l, v, t = hangul.decompose(0xAC01)
  self:assert_equal(0x1100, l)
  self:assert_equal(0x1161, v)
  self:assert_equal(0x11A8, t)
  l, v, t = hangul.decompose(0xD7A3)
  self:assert_equal(0x1112, l)
  self:assert_equal(0x1175, v)
  self:assert_equal(0x11C2, t)
end

function T:test_composition_inverts_decomposition_for_every_syllable()
  for syllable = 0xAC00, 0xD7A3 do
    local l, v, t = hangul.decompose(syllable)
    local lv = hangul.compose(l, v)
    self:assert_equal(t and 0xAC00 + ((syllable - 0xAC00) // 28) * 28 or syllable, lv, ("%X"):format(syllable))
    if t then self:assert_equal(syllable, hangul.compose(lv, t)) end
  end
end

function T:test_pairs_that_do_not_compose()
  self:assert_nil(hangul.compose(0x1100, 0x1100))
  self:assert_nil(hangul.compose(0x1161, 0x1100))
  self:assert_nil(hangul.compose(0xAC01, 0x11A8), "an LVT syllable takes no trailing consonant")
  self:assert_nil(hangul.compose(0xAC00, 0x11A7), "TBase itself is not a trailing consonant")
  self:assert_nil(hangul.compose(0x41, 0x42))
end

return T
