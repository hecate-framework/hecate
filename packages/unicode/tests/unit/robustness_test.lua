---@diagnostic disable: param-type-mismatch, undefined-field  -- the four functions are called by name
-- Seeded random inputs: the contract of the four functions on any string, and the shared tables that no call may alter.
local test = require("harness.test")
local core = require("hecate.core")
local unicode = require("hecate.unicode")
local tables = require("hecate.unicode.internal.tables")
local T = test.Case("UnicodeRobustnessTest")

-- Code points that exercise every path: ASCII, Latin letters and marks, singletons, Hangul syllables and jamo, a
-- mark that decomposes (U+0344), an unassigned code point, the extremes.
local POOL = { 0x41, 0x61, 0x65, 0x69, 0x300, 0x301, 0x302, 0x307, 0x308, 0x323, 0x326, 0x344, 0xC0, 0xE9, 0x1EAD, 0x1F71,
  0x212B, 0x2126, 0x3B1, 0x3B9, 0x435, 0x438, 0x306, 0x1100, 0x1161, 0x11A8, 0xAC00, 0xAC01, 0xD7A3, 0x378, 0x4E2D,
  0x1D15E, 0x10FFFF, 0x7F, 0x80, 0xFFFD }

local function valid_string()
  local list = {}
  for index = 1, math.random(0, 14) do list[index] = utf8.char(POOL[math.random(1, #POOL)]) end
  return table.concat(list)
end

local function random_bytes()
  local list = {}
  for index = 1, math.random(0, 12) do
    -- Half of the bytes are high ones: leading, continuation and never-valid bytes.
    list[index] = string.char(math.random(0, 1) == 1 and math.random(0x80, 0xFF) or math.random(0, 0x7F))
  end
  return table.concat(list)
end

--- A valid string with one byte changed or removed (the near misses: overlong forms, surrogates, truncations).
local function damaged()
  local text = valid_string() .. utf8.char(POOL[math.random(1, #POOL)])
  local position = math.random(1, #text)
  local kind = math.random(1, 3)
  if kind == 1 then return text:sub(1, position - 1) .. string.char(math.random(0, 255)) .. text:sub(position + 1) end
  if kind == 2 then return text:sub(1, position - 1) .. text:sub(position + 1) end
  return text:sub(1, position)
end

local function sample(round)
  local kind = round % 3
  if kind == 0 then return valid_string() end
  if kind == 1 then return random_bytes() end
  return damaged()
end

function T:test_every_function_errors_exactly_when_the_string_is_not_well_formed_utf8()
  math.randomseed(1119)
  local invalid, valid = 0, 0
  for round = 1, 3000 do
    local text = sample(round)
    for _, name in ipairs({ "nfc", "nfd", "is_nfc", "is_nfd" }) do
      local ok, result = pcall(unicode[name], text)
      if utf8.len(text) == nil then
        self:assert_false(ok, ("%s accepted %q"):format(name, text))
        self:assert_true(core.is_instance_of(result, unicode.InvalidUtf8Error), ("%s on %q: %s"):format(name, text, tostring(result)))
        self:assert_true(type(result.context.position) == "number" and result.context.position >= 1)
      else
        self:assert_true(ok, ("%s refused %q: %s"):format(name, text, tostring(result)))
      end
    end
    if utf8.len(text) == nil then invalid = invalid + 1 else valid = valid + 1 end
  end
  self:assert_true(invalid > 500 and valid > 500, ("the sample covers both sides (%d invalid, %d valid)"):format(invalid, valid))
end

function T:test_the_known_malformed_forms_are_refused()
  for _, text in ipairs({ "\xED\xA0\x80", "\xC0\x80", "\xE0\x80\x80", "\xF4\x90\x80\x80", "\x80", "a\xC3", "\xFF", "e\u{301}\xFF" }) do
    for _, name in ipairs({ "nfc", "nfd", "is_nfc", "is_nfd" }) do
      local err = self:assert_error(function() unicode[name](text) end)
      self:assert_true(core.is_instance_of(err, unicode.InvalidUtf8Error), ("%s %q"):format(name, text))
    end
  end
end

function T:test_the_output_is_well_formed_idempotent_and_the_two_forms_agree()
  math.randomseed(1120)
  for _ = 1, 3000 do
    local text = valid_string()
    local composed, decomposed = unicode.nfc(text), unicode.nfd(text)
    self:assert_not_nil(utf8.len(composed), ("NFC of %q is not UTF-8"):format(text))
    self:assert_not_nil(utf8.len(decomposed), ("NFD of %q is not UTF-8"):format(text))
    self:assert_equal(composed, unicode.nfc(composed), ("NFC is not idempotent on %q"):format(text))
    self:assert_equal(decomposed, unicode.nfd(decomposed), ("NFD is not idempotent on %q"):format(text))
    self:assert_equal(composed, unicode.nfc(decomposed), ("nfc(nfd(x)) differs from nfc(x) on %q"):format(text))
    self:assert_equal(decomposed, unicode.nfd(composed), ("nfd(nfc(x)) differs from nfd(x) on %q"):format(text))
    self:assert_equal(composed == text, unicode.is_nfc(text))
    self:assert_equal(decomposed == text, unicode.is_nfd(text))
    self:assert_true(unicode.is_nfc(composed) and unicode.is_nfd(decomposed))
  end
end

function T:test_normalisation_never_changes_the_text_of_an_ascii_string_or_loses_a_code_point_of_a_starter_only_string()
  math.randomseed(1121)
  for _ = 1, 500 do
    local list = {}
    for index = 1, math.random(0, 30) do list[index] = string.char(math.random(0, 127)) end
    local text = table.concat(list)
    self:assert_equal(text, unicode.nfc(text))
    self:assert_equal(text, unicode.nfd(text))
  end
end

-- A serialisation of everything the algorithm reads: the lookups of the data, in the order of their keys.
local function fingerprint()
  local loaded = tables.get()
  local keys = {}
  local function visit(label, map)
    local names = {}
    for key in pairs(map) do names[#names + 1] = key end
    table.sort(names)
    for _, key in ipairs(names) do
      local value = map[key]
      if type(value) == "table" then
        local parts = {}
        local inner = {}
        for k in pairs(value) do inner[#inner + 1] = k end
        table.sort(inner)
        for _, k in ipairs(inner) do parts[#parts + 1] = k .. "=" .. value[k] end
        keys[#keys + 1] = label .. key .. ":" .. table.concat(parts, ",")
      else
        keys[#keys + 1] = label .. key .. ":" .. value
      end
    end
  end
  visit("c", loaded.combining_class)
  visit("d", loaded.decomposition)
  visit("p", loaded.composition)
  return #keys, table.concat(keys, ";")
end

-- The tables are shared by every caller of the process and read-only by contract: `hecate.unicode` copies a
-- decomposition into its working array and never writes to a table it was given. A mutation that aliased the array of a
-- decomposition (an `out` that is the table of the data) would change the data of the next call.
function T:test_no_call_alters_the_shared_tables()
  local count, before = fingerprint()
  self:assert_true(count > 1000)
  math.randomseed(1122)
  for round = 1, 400 do
    local text = sample(round * 3) -- valid strings only: the others raise before any table is read
    unicode.nfc(text)
    unicode.nfd(text)
  end
  unicode.nfc(("a\u{323}\u{302}\u{301}\u{1EAD}\u{AC01}\u{212B}"):rep(50))
  unicode.nfd(("\u{1EAD}\u{1F71}\u{344}"):rep(50))
  local _, after = fingerprint()
  self:assert_true(before == after, "a call changed the tables of the data")
  self:assert_true(tables.get() == tables.get(), "one loaded copy, shared")
end

function T:test_a_decomposition_in_the_result_is_a_copy_of_the_table_not_the_table()
  local loaded = tables.get()
  local parts = loaded.decomposition[0x1EAD]
  local snapshot = table.concat(parts, ",")
  local result = unicode.nfd("\u{1EAD}")
  self:assert_equal("a\u{323}\u{302}", result)
  self:assert_equal(snapshot, table.concat(loaded.decomposition[0x1EAD], ","))
  self:assert_equal(3, #loaded.decomposition[0x1EAD], "the entry still holds three code points")
end

return T
