-- What the native decoder promises about a failure, next to the reference decoder (the oracle).
--
-- The native decoder reports the failures of yyjson (a code, a message and a byte position) in the vocabulary of the codec,
-- without a second parse. Guaranteed: the same verdict (a text is accepted by both or rejected by both) and the same
-- value when accepted; for a rejection, the same reason and the same offset. Not guaranteed, and accepted as limits of
-- the dependency (docs/open-questions.md, OQ-54):
--   * the message: yyjson cannot say what was expected, so the reference decoder is more precise;
--   * a duplicate member name has no offset in the native decoder (yyjson keeps no position for it);
--   * duplicate member names are found after the parse, so a text that has one and another defect later (a syntax
--     error, a number out of range) is reported by the native decoder as that defect (the reference decoder meets the
--     duplicate first);
--   * a text with several defects: yyjson may stop at another one than the reference decoder (earlier or later), so the
--     offset is compared only on texts with a single defect (`strict`: the hand-written corpus and the suites), not on
--     mutated texts;
--   * when a string has several defects, or a defect and an unterminated end, the two decoders may name a different
--     one (a bad escape, a lone surrogate, an invalid UTF-8 byte, a control character, an unterminated string): the
--     reasons of that family are interchangeable, and the offsets are then not compared.
-- Returns nil when the failures are compatible, else a description.
local STRING_DEFECTS = {
  syntax = true, invalid_utf8 = true, invalid_escape = true, lone_surrogate = true, control_character = true,
}

---@param want { reason: string, offset: integer?, message: string }  from the reference decoder
---@param got { reason: string, offset: integer?, message: string }  from the native decoder
---@param strict boolean?  also compare the offset of a failure (texts with a single defect)
---@return string?
return function(want, got, strict)
  if want.reason == got.reason then
    if want.reason == "duplicate_key" then
      if got.offset ~= nil then return "the native decoder gave an offset for a duplicate member name" end
      return nil
    end
    if strict and want.offset ~= got.offset then
      return ("offset differs: %s (%s) / %s (%s)"):format(tostring(want.offset), want.reason, tostring(got.offset), got.reason)
    end
    return nil
  end
  if STRING_DEFECTS[want.reason] and STRING_DEFECTS[got.reason] then return nil end
  -- found after the parse: any other defect of the text is reported first by the native decoder
  if want.reason == "duplicate_key" and not strict then return nil end
  return ("reason differs: %s at %s / %s at %s"):format(want.reason, tostring(want.offset), got.reason, tostring(got.offset))
end
