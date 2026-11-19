-- Hangul syllable arithmetic (Unicode Standard 3.12, "Conjoining Jamo Behavior", Hangul Syllable Decomposition and
-- Hangul Syllable Composition). The 11172 precomposed syllables U+AC00 to U+D7A3 are not in the data tables: their
-- canonical decomposition is computed.
global none

local hangul = {}

local SBASE, LBASE, VBASE, TBASE = 0xAC00, 0x1100, 0x1161, 0x11A7
local LCOUNT, VCOUNT, TCOUNT = 19, 21, 28
local NCOUNT = VCOUNT * TCOUNT
local SCOUNT = LCOUNT * NCOUNT

--- The number of precomposed syllables.
hangul.SCOUNT = SCOUNT

--- True for a precomposed Hangul syllable.
---@param codepoint integer
---@return boolean
function hangul.is_syllable(codepoint) return codepoint >= SBASE and codepoint < SBASE + SCOUNT end

--- The canonical decomposition of a syllable: leading consonant, vowel and, when the syllable has one, the trailing
--- consonant (nil otherwise).
---@param syllable integer
---@return integer leading
---@return integer vowel
---@return integer? trailing
function hangul.decompose(syllable)
  local index = syllable - SBASE
  local trailing = index % TCOUNT
  return LBASE + index // NCOUNT, VBASE + (index % NCOUNT) // TCOUNT, trailing ~= 0 and (TBASE + trailing) or nil
end

--- The primary composite of two code points when they are a leading consonant and a vowel, or a syllable without
--- trailing consonant and a trailing consonant; nil otherwise.
---@param first integer
---@param second integer
---@return integer?
function hangul.compose(first, second)
  if first >= LBASE and first < LBASE + LCOUNT then
    if second >= VBASE and second < VBASE + VCOUNT then
      return SBASE + ((first - LBASE) * VCOUNT + (second - VBASE)) * TCOUNT
    end
  elseif first >= SBASE and first < SBASE + SCOUNT and (first - SBASE) % TCOUNT == 0 then
    if second > TBASE and second < TBASE + TCOUNT then return first + (second - TBASE) end
  end
  return nil
end

return hangul
