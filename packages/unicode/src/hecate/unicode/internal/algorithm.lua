-- Normalisation Forms D and C (Unicode Standard 3.11, "Normalization Forms"; UAX #15, "Normalization Forms").
--
-- NFD is the full canonical decomposition of every code point (the Hangul syllables by arithmetic, 3.12) followed by the
-- Canonical Ordering Algorithm (3.11, D109: a stable sort of each run of non-starters by canonical combining class).
-- NFC is NFD followed by the canonical composition algorithm (UAX #15, "Canonical Composition Algorithm": each
-- character is composed with the last starter unless it is blocked, D115 and D117).
global <const> require, utf8, table

local hangul = require("hecate.unicode.internal.hangul")

local algorithm = {}

-- Runs of non-starters at most this long are ordered by insertion; a longer run is sorted with integer keys, so that a
-- hostile string of thousands of marks costs n log n and not n squared.
-- The limit is a field so that a test can force either path (it is read once per call of `reorder`).
algorithm.INSERTION_LIMIT = 24

--- Appends the full canonical decomposition of every code point of `text` (well-formed UTF-8) to `out`; returns the count.
local function decompose(text, tables)
  local decomposition = tables.decomposition
  local out, n = {}, 0
  for _, codepoint in utf8.codes(text) do
    if codepoint < 0xC0 then -- the first code point with a canonical decomposition is U+00C0
      n = n + 1
      out[n] = codepoint
    elseif hangul.is_syllable(codepoint) then
      local leading, vowel, trailing = hangul.decompose(codepoint)
      out[n + 1], out[n + 2] = leading, vowel
      n = n + 2
      if trailing then
        n = n + 1
        out[n] = trailing
      end
    else
      local parts = decomposition[codepoint]
      if parts then
        for i = 1, #parts do out[n + i] = parts[i] end
        n = n + #parts
      else
        n = n + 1
        out[n] = codepoint
      end
    end
  end
  return out, n
end

--- Canonical ordering of the runs of non-starters, in place (stable).
local function reorder(out, n, classes)
  local limit = algorithm.INSERTION_LIMIT
  local i = 1
  while i <= n do
    if classes[out[i]] then
      local j = i
      while j < n and classes[out[j + 1]] do j = j + 1 end
      if j > i then
        local length = j - i + 1
        if length <= limit then
          for k = i + 1, j do
            local codepoint = out[k]
            local class = classes[codepoint]
            local m = k - 1
            while m >= i and classes[out[m]] > class do
              out[m + 1] = out[m]
              m = m - 1
            end
            out[m + 1] = codepoint
          end
        else
          -- Key = class and original position: the sort of the keys is the stable sort of the marks.
          local keys, marks = {}, {}
          for k = 1, length do
            local codepoint = out[i + k - 1]
            marks[k] = codepoint
            keys[k] = (classes[codepoint] << 32) | k
          end
          table.sort(keys)
          for k = 1, length do out[i + k - 1] = marks[keys[k] & 0xFFFFFFFF] end
        end
      end
      i = j + 1
    else
      i = i + 1
    end
  end
end

--- The canonical composition of `out` (already decomposed and ordered); returns the new array and its length.
local function compose(out, n, tables)
  local classes, composition = tables.combining_class, tables.composition
  local result, m = {}, 0
  local starter -- index in `result` of the last starter
  local last_class = 0
  for i = 1, n do
    local codepoint = out[i]
    local class = classes[codepoint] or 0
    local composed
    if starter and (last_class < class or last_class == 0) then
      local first = result[starter]
      composed = hangul.compose(first, codepoint)
      if not composed then
        local row = composition[first]
        composed = row and row[codepoint]
      end
    end
    if composed then
      result[starter] = composed
    else
      if class == 0 then starter = m + 1 end
      last_class = class
      m = m + 1
      result[m] = codepoint
    end
  end
  return result, m
end

local function encode(codepoints, n)
  -- One `utf8.char` per code point: `table.unpack` would fail on a string with more code points than the stack holds.
  local pieces = {}
  for i = 1, n do pieces[i] = utf8.char(codepoints[i]) end
  return table.concat(pieces)
end

--- Normalises well-formed UTF-8 text without a byte above 0x7F removed from the caller: ASCII is returned as it is.
---@param text string  well-formed UTF-8
---@param compose_result boolean  true for NFC, false for NFD
---@param tables hecate.unicode.Tables
---@return string
function algorithm.normalise(text, compose_result, tables)
  if not text:find("[\128-\255]") then return text end
  local out, n = decompose(text, tables)
  reorder(out, n, tables.combining_class)
  if compose_result then out, n = compose(out, n, tables) end
  return encode(out, n)
end

return algorithm
