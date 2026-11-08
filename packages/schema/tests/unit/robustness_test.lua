---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
-- Seeded robustness tests of the parser-like pieces (review finding q1): the `pattern` translator and the `format`
-- validators. Deterministic (fixed seed, `HECATE_TEST_SEED` to change it, printed by a failure), no clock: the work is
-- bounded by the length of the inputs.
--
-- Translator: for random patterns (a grammar of Lua pattern pieces, and soups of syntax characters and random bytes)
-- `to_ecma` and `check` raise nothing but `ArgumentError`, return a string bounded in the length of the pattern, the output is
-- well formed by a structural check, a well-formed pattern never makes Lua raise a malformed-pattern error, and for ASCII
-- subjects the output accepts exactly what Lua accepts (the matcher of tests/support/ecma.lua).
-- Formats: on random byte strings (invalid UTF-8, control characters, near misses of valid samples) `validate` never raises and
-- gives a boolean verdict; a list of known good and known bad samples fixes the verdict of each format.
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local translate = require("hecate.schema.pattern")
local T = test.Case("SchemaRobustnessTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local prng = dofile(here .. "/../support/prng.lua")
local ecma = dofile(here .. "/../support/ecma.lua")

local CASES = 1500

-- Patterns -------------------------------------------------------------------------------------------------------------------

local ATOMS = { "a", "b", "c", "1", "2", " ", "_", "%.", "%-", "%%", "%a", "%d", "%w", "%s", "%l", "%u", "%p", "%A", "%D",
  "%W", ".", "[abc]", "[^a]", "[a-c]", "[%d_]", "[^%s]", "[%a-]", "[]a]" }
local QUANTIFIERS = { "", "", "", "*", "+", "?", "-" }
-- Pieces the translator refuses or Lua rejects (or that are well formed but outside the supported subset).
local ODD = { "%b()", "%f[a]", "%", "[", "[a", "(", ")", "%1", "%z", "caf\xC3\xA9", "()", "%g", "[%S]", "\0", "\xff", "[a-", "%x" }

local function gen_sequence(rng, depth)
  local parts = {}
  for _ = 1, rng.int(1, 4) do
    if depth > 0 and rng.chance(1, 8) then
      parts[#parts + 1] = "(" .. gen_sequence(rng, depth - 1) .. ")"
    else
      parts[#parts + 1] = rng.pick(ATOMS) .. rng.pick(QUANTIFIERS)
    end
  end
  return table.concat(parts)
end

local function gen_pattern(rng)
  local roll = rng.int(1, 10)
  if roll <= 6 then
    return (rng.chance(1, 4) and "^" or "") .. gen_sequence(rng, 2) .. (rng.chance(1, 4) and "$" or "")
  elseif roll <= 8 then
    return gen_sequence(rng, 1) .. rng.pick(ODD) .. gen_sequence(rng, 1)
  elseif roll == 9 then
    local soup = { "%", "[", "]", "(", ")", "^", "$", ".", "*", "+", "-", "?", "a", "b", "1", "%a", "%1" }
    local parts = {}
    for i = 1, rng.int(0, 12) do parts[i] = rng.pick(soup) end
    return table.concat(parts)
  end
  local bytes = {}
  for i = 1, rng.int(0, 12) do bytes[i] = string.char(rng.int(0, 255)) end
  return table.concat(bytes)
end

--- Structural check of an emitted expression: brackets and groups balance, an escape is followed by a character,
--- a set is closed, and no quantifier opens the expression or follows another one (except the lazy `?`).
local function well_formed(re)
  local i, groups = 1, 0
  local previous_quantifier = false
  local at_start = true
  while i <= #re do
    local c = re:sub(i, i)
    local quantifier = false
    if c == "\\" then
      if i == #re then return false, "dangling escape" end
      i = i + 1
    elseif c == "[" then
      local j = i + 1
      if re:sub(j, j) == "^" then j = j + 1 end
      local closed = false
      while j <= #re do
        local d = re:sub(j, j)
        if d == "\\" then j = j + 1
        elseif d == "]" then closed = true break end
        j = j + 1
      end
      if not closed then return false, "unclosed set" end
      i = j
    elseif c == "(" then
      groups = groups + 1
    elseif c == ")" then
      groups = groups - 1
      if groups < 0 then return false, "unbalanced )" end
    elseif c == "?" and re:sub(i - 1, i - 1) == "(" then
      -- `(?:` opens a non-capturing group
    elseif c == "*" or c == "+" or c == "?" then
      quantifier = true
      if at_start then return false, "quantifier at the start" end
      if previous_quantifier and c ~= "?" then return false, "stacked quantifiers" end
    end
    previous_quantifier = quantifier and not (c == "?" and previous_quantifier)
    at_start = c == "(" or c == "^" and at_start
    i = i + 1
  end
  if groups ~= 0 then return false, "unclosed group" end
  return true
end

local SUBJECT_ALPHABET = { "a", "b", "c", "1", "9", "0", "z", "Z", " ", "\t", "_", ".", "-", "A", "%", "(", ")", "!", "~" }

local function gen_subject(rng)
  local parts = {}
  for i = 1, rng.int(0, 6) do parts[i] = rng.pick(SUBJECT_ALPHABET) end
  return table.concat(parts)
end

function T:test_the_translator_raises_only_argument_errors_and_emits_well_formed_bounded_output()
  prng.run(0x7A11, function(rng)
    local translated, refused = 0, 0
    for _ = 1, CASES do
      local pattern = gen_pattern(rng)
      local label = ("pattern %q"):format(pattern)
      local ok, result = pcall(translate.to_ecma, pattern)
      if ok then
        translated = translated + 1
        self:assert_equal("string", type(result), label)
        -- bounded: the longest expansion of one character is a class of fewer than 40 bytes
        self:assert_true(#result <= 40 * #pattern + 8, label .. ": output of " .. #result .. " bytes")
        local well, why = well_formed(result)
        self:assert_true(well, ("%s -> %s: %s"):format(label, result, tostring(why)))
      else
        refused = refused + 1
        self:assert_true(core.is_instance_of(result, core.ArgumentError), label .. ": raised " .. tostring(result))
      end
      local checked_ok, reason = pcall(translate.check, pattern)
      self:assert_true(checked_ok, label .. ": check raised " .. tostring(reason))
      self:assert_true(reason == nil or type(reason) == "string", label)
    end
    self:assert_true(translated >= CASES // 3, "translated only " .. translated)
    self:assert_true(refused >= CASES // 10, "refused only " .. refused)
  end)
end

function T:test_a_pattern_that_check_accepts_never_makes_lua_raise_a_malformed_pattern_error()
  prng.run(0x7A12, function(rng)
    for _ = 1, CASES do
      local pattern = gen_pattern(rng)
      if translate.check(pattern) == nil then
        for _ = 1, 3 do
          local ok, err = pcall(string.find, gen_subject(rng), pattern)
          self:assert_true(ok, ("pattern %q accepted by check, Lua raised %s"):format(pattern, tostring(err)))
        end
      end
    end
  end)
end

function T:test_the_emitted_expression_accepts_what_lua_accepts_on_ascii_subjects()
  prng.run(0x7A13, function(rng)
    local compared = 0
    for _ = 1, CASES do
      local pattern = gen_sequence(rng, 2)
      if rng.chance(1, 4) then pattern = "^" .. pattern end
      if rng.chance(1, 4) then pattern = pattern .. "$" end
      local ok, re = pcall(translate.to_ecma, pattern)
      if ok then
        for _ = 1, 4 do
          local subject = gen_subject(rng)
          local matched_ok, matched = pcall(ecma.matches, re, subject)
          if matched_ok then
            compared = compared + 1
            self:assert_equal(subject:find(pattern) ~= nil, matched,
              ("pattern %q (%s) on %q"):format(pattern, re, subject))
          else
            -- outside the subset of the test matcher: only a back reference or a non-capturing group may be
            self:assert_true(re:find("(?:", 1, true) ~= nil, ("matcher failed on %s: %s"):format(re, tostring(matched)))
          end
        end
      end
    end
    self:assert_true(compared >= 2000, "only " .. compared .. " comparisons")
  end)
end

function T:test_the_translator_agrees_with_a_short_list_of_known_patterns()
  self:assert_equal("^[0-9]+$", translate.to_ecma("^%d+$"))
  self:assert_equal("a\\.b", translate.to_ecma("a%.b"))
  self:assert_true(translate.check("^%d+$") == nil)
  self:assert_true(type(translate.check("a%")) == "string")
  self:assert_true(type(translate.check("[a")) == "string")
  self:assert_true(type(translate.check("(a")) == "string")
  for _, refused in ipairs({ "%bxy", "%f[a]", "caf\xC3\xA9" }) do
    self:assert_false(pcall(translate.to_ecma, refused), refused)
    self:assert_true(translate.check(refused) == nil, "well formed, only not translatable: " .. refused)
  end
end

-- Formats --------------------------------------------------------------------------------------------------------------------

local FORMATS = { "uuid", "date", "date-time", "email", "ipv4", "uri" }

local GOOD = {
  uuid = { "123e4567-e89b-12d3-a456-426614174000", "00000000-0000-0000-0000-000000000000",
    "123E4567-E89B-12D3-A456-426614174000" },
  date = { "2024-02-29", "2000-01-01", "1999-12-31" },
  ["date-time"] = { "2024-02-29T12:00:00Z", "2024-01-01T00:00:00+01:00", "2024-01-01T23:59:59.123Z",
    "1999-12-31T23:59:59-08:00" },
  email = { "a@b.co", "first.last@example.com", "a+tag@sub.example.org" },
  ipv4 = { "0.0.0.0", "255.255.255.255", "192.168.1.1" },
  uri = { "http://example.com", "https://a.b/c?d=e#f", "ftp://host/path" },
}

local BAD = {
  uuid = { "", "123e4567e89b12d3a456426614174000", "123e4567-e89b-12d3-a456-42661417400",
    "g23e4567-e89b-12d3-a456-426614174000", "123e4567-e89b-12d3-a456-426614174000\n", " 123e4567-e89b-12d3-a456-426614174000" },
  date = { "", "2023-02-29", "2024-13-01", "2024-00-10", "2024-1-1", "24-01-01", "2024-01-32", "2024-01-01 " },
  ["date-time"] = { "", "2024-01-01", "2024-01-01T24:00:00Z", "2024-01-01T12:00:00", "2024-02-30T00:00:00Z",
    "2024-01-01T00:00:00Z\n" },
  email = { "", "a", "a@", "@b.co", "a b@c.de", "a@b.co\n", ("a"):rep(250) .. "@b.co", "a\0@b.co", "a\1@b.co" },
  ipv4 = { "", "256.1.1.1", "1.2.3", "1.2.3.4.5", "a.b.c.d", "1.2.3.4 ", "1..2.3", "1.2.3.4\n" },
  uri = { "", "example.com", "//a", "http://a b", "http://a\nb", "1http://a", "http://a\0" },
}

local function verdict(format, text)
  local ok, result = pcall(function() return (schema.string({ format = format }):validate(text)) end)
  return ok, result
end

function T:test_known_good_and_bad_samples()
  for _, format in ipairs(FORMATS) do
    for _, text in ipairs(GOOD[format]) do
      local ok, result = verdict(format, text)
      self:assert_true(ok, format .. " raised on " .. ("%q"):format(text))
      self:assert_true(result, ("%s should accept %q"):format(format, text))
    end
    for _, text in ipairs(BAD[format]) do
      local ok, result = verdict(format, text)
      self:assert_true(ok, format .. " raised on " .. ("%q"):format(text))
      self:assert_false(result, ("%s should refuse %q"):format(format, text))
    end
  end
end

local CONTROLS = { "\0", "\1", "\n", "\r", "\t", "\127", "\xff", "\xc3", "\xe2\x82", "\xf0\x9f\x98\x80", "\xed\xa0\x80", "\xc0\xaf" }

local function random_text(rng)
  local roll = rng.int(1, 4)
  local parts = {}
  if roll == 1 then
    for i = 1, rng.int(0, 40) do parts[i] = string.char(rng.int(0, 255)) end
  elseif roll == 2 then
    for i = 1, rng.int(0, 30) do
      parts[i] = rng.chance(1, 4) and rng.pick(CONTROLS) or string.char(rng.int(32, 126))
    end
  else
    -- a near miss of a valid sample of a random format: one byte replaced, deleted or inserted
    local format = rng.pick(FORMATS)
    local sample = rng.pick(GOOD[format])
    local at = rng.int(1, #sample)
    local edit = rng.int(1, 3)
    local byte = rng.chance(1, 2) and rng.pick(CONTROLS) or string.char(rng.int(0, 255))
    if edit == 1 then sample = sample:sub(1, at - 1) .. byte .. sample:sub(at + 1)
    elseif edit == 2 then sample = sample:sub(1, at - 1) .. sample:sub(at + 1)
    else sample = sample:sub(1, at) .. byte .. sample:sub(at + 1) end
    return sample
  end
  return table.concat(parts)
end

function T:test_random_byte_strings_never_raise_and_give_a_boolean_verdict()
  prng.run(0xF0A7, function(rng)
    local schemas = {}
    for _, format in ipairs(FORMATS) do schemas[format] = schema.string({ format = format }) end
    local accepted = 0
    for _ = 1, CASES do
      local text = random_text(rng)
      for _, format in ipairs(FORMATS) do
        local ok, verdict_ok, violations = pcall(schemas[format].validate, schemas[format], text)
        local label = ("%s on %q"):format(format, text)
        self:assert_true(ok, label .. ": raised " .. tostring(verdict_ok))
        self:assert_equal("boolean", type(verdict_ok), label)
        if verdict_ok then
          accepted = accepted + 1
        else
          self:assert_equal("format", violations[1].code, label)
          self:assert_equal("string", type(violations[1].message), label)
          if #text >= 8 then -- a shorter text would be found in any English message by chance
            self:assert_nil(violations[1].message:find(text, 1, true), label .. ": the message echoes the text")
          end
        end
      end
    end
    -- near misses of valid samples are accepted now and then (a replaced digit stays a digit): not all verdicts are `false`
    self:assert_true(accepted > 0, "no random text was ever accepted: the generator never reaches the valid side")
  end)
end

function T:test_a_format_verdict_does_not_depend_on_what_was_validated_before()
  prng.run(0xF0A8, function(rng)
    local s = schema.string({ format = "email" })
    for _ = 1, 300 do
      local text = random_text(rng)
      local first = s:validate(text)
      s:validate(random_text(rng))
      self:assert_equal(first, (s:validate(text)), ("%q"):format(text))
    end
  end)
end

return T
