-- NormalizationTest.txt of the Unicode version of the data rock (UAX #15, "Conformance Testing"; downloaded by
-- `fetch-fixtures unicode`, not vendored, pinned by its SHA-256 in tests/external.lua; ADR 0032): every line of every
-- part, the NFC and NFD columns at 100%, plus the invariance of each code point that Part 1 does not list.
-- Locally the suite skips without the file; in CI a missing file is a failure.
local test = require("harness.test")
local unicode = require("hecate.unicode")
local T = test.Case("NormalizationConformanceTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local path = here .. "/../../../../.hecate/fixtures/unicode/NormalizationTest.txt"

local function read()
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

local function present(self)
  local text = read()
  if text then return text end
  if os.getenv("CI") then self:fail("NormalizationTest.txt is missing (lua tools/run.lua fetch-fixtures unicode)") end
  io.stderr:write("# skipped: NormalizationTest.txt is missing (lua tools/run.lua fetch-fixtures unicode)\n")
  return nil
end

local function sequence(column)
  local list = {}
  for hex in column:gmatch("%x+") do list[#list + 1] = tonumber(hex, 16) end
  return utf8.char(table.unpack(list))
end

--- The cases of the file: { line, part, c1..c5 as strings }, and the set of the code points listed alone in Part 1.
local function parse(text)
  local cases, listed, part = {}, {}, nil
  local number = 0
  for line in text:gmatch("([^\n]*)\n?") do
    number = number + 1
    local name = line:match("^@(Part%d)")
    if name then
      part = name
    elseif line ~= "" and not line:find("^#") then
      local columns = {}
      for column in line:gsub("#.*$", ""):gmatch("([^;]*);") do columns[#columns + 1] = column end
      assert(#columns >= 5, "line " .. number)
      local case = { line = number, part = part }
      for i = 1, 5 do case[i] = sequence(columns[i]) end
      cases[#cases + 1] = case
      if part == "Part1" then listed[utf8.codepoint(case[1])] = true end
    end
  end
  return cases, listed
end

local function shown(text)
  local out = {}
  for _, codepoint in utf8.codes(text) do out[#out + 1] = ("%04X"):format(codepoint) end
  return table.concat(out, " ")
end

function T:test_the_fixture_is_the_version_of_the_data()
  local text = present(self)
  if not text then return end
  self:assert_equal("NormalizationTest-" .. unicode.unicode_version .. ".txt", text:match("^# (NormalizationTest%-[%d%.]+%.txt)"))
end

function T:test_every_line_of_every_part_in_the_nfc_and_nfd_columns()
  local text = present(self)
  if not text then return end
  local cases = parse(text)
  self:assert_true(#cases > 19000, "the file has more than 19000 test cases")
  local failures, parts = {}, {}
  local function check(case, label, expected, actual)
    if expected ~= actual then
      failures[#failures + 1] = ("line %d (%s) %s: expected %s, got %s"):format(case.line, case.part, label, shown(expected), shown(actual))
    end
  end
  for _, case in ipairs(cases) do
    parts[case.part] = (parts[case.part] or 0) + 1
    local c1, c2, c3, c4, c5 = case[1], case[2], case[3], case[4], case[5]
    check(case, "NFC(c1)", c2, unicode.nfc(c1))
    check(case, "NFC(c2)", c2, unicode.nfc(c2))
    check(case, "NFC(c3)", c2, unicode.nfc(c3))
    check(case, "NFC(c4)", c4, unicode.nfc(c4))
    check(case, "NFC(c5)", c4, unicode.nfc(c5))
    check(case, "NFD(c1)", c3, unicode.nfd(c1))
    check(case, "NFD(c2)", c3, unicode.nfd(c2))
    check(case, "NFD(c3)", c3, unicode.nfd(c3))
    check(case, "NFD(c4)", c5, unicode.nfd(c4))
    check(case, "NFD(c5)", c5, unicode.nfd(c5))
    -- Idempotence of both forms on every column.
    for _, column in ipairs(case) do
      local composed, decomposed = unicode.nfc(column), unicode.nfd(column)
      check(case, "NFC idempotent", composed, unicode.nfc(composed))
      check(case, "NFD idempotent", decomposed, unicode.nfd(decomposed))
    end
  end
  for _, part in ipairs({ "Part0", "Part1", "Part2", "Part3", "Part4", "Part5" }) do
    self:assert_true((parts[part] or 0) > 0, part .. " has test cases")
  end
  if #failures > 0 then
    self:fail(("%d of %d columns failed; the first ones:\n%s"):format(#failures, #cases * 20,
      table.concat(failures, "\n", 1, math.min(#failures, 10))))
  end
end

function T:test_every_code_point_that_part_1_does_not_list_is_invariant()
  local text = present(self)
  if not text then return end
  local _, listed = parse(text)
  local failures = 0
  local first
  for codepoint = 0, 0x10FFFF do
    if (codepoint < 0xD800 or codepoint > 0xDFFF) and not listed[codepoint] then
      local character = utf8.char(codepoint)
      if unicode.nfc(character) ~= character or unicode.nfd(character) ~= character then
        failures = failures + 1
        first = first or codepoint
      end
    end
  end
  self:assert_equal(0, failures, ("%d code points not listed in Part 1 change; the first is U+%04X"):format(failures, first or 0))
end

return T
