---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local data = require("hecate.unicode_data")
local T = test.Case("UnicodeDataTest")

function T:test_the_version_and_the_layout_are_declared()
  self:assert_equal("string", type(data.unicode_version))
  self:assert_true(data.unicode_version:match("^%d+%.%d+%.%d+$") ~= nil)
  self:assert_equal(1, data.format)
  self:assert_true(math.type(data.format) == "integer")
end

function T:test_the_unicode_version_is_the_one_pinned_for_the_generator()
  local external = assert(loadfile((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../external.lua"))()
  for _, entry in ipairs(external) do
    self:assert_true(entry.url:find("/Public/" .. data.unicode_version .. "/ucd/", 1, true) ~= nil, entry.name)
  end
end

function T:test_only_the_three_tables_load()
  for _, name in ipairs({ "combining_class", "decomposition", "composition" }) do self:assert_equal("table", type(data.load(name))) end
  self:assert_error(function() data.load("nothing") end, "unknown Unicode data table")
  self:assert_error(function() data.load("../init") end, "unknown Unicode data table")
  self:assert_error(function() data.load(nil) end, "unknown Unicode data table")
end

function T:test_the_combining_classes_are_sorted_disjoint_ranges()
  local flat = data.load("combining_class")
  self:assert_equal(0, #flat % 3)
  self:assert_true(#flat > 0)
  local previous = -1
  for i = 1, #flat, 3 do
    self:assert_true(flat[i] <= flat[i + 1], "first <= last")
    self:assert_true(flat[i] > previous, "ascending and disjoint")
    self:assert_true(flat[i + 2] >= 1 and flat[i + 2] <= 255, "class in 1..255")
    previous = flat[i + 1]
  end
end

function T:test_known_entries()
  local decomposition, composition = data.load("decomposition"), data.load("composition")
  self:assert_equal(0x41, decomposition[0xC0][1])
  self:assert_equal(0x300, decomposition[0xC0][2])
  self:assert_equal(0x3A9, decomposition[0x2126][1], "singleton")
  self:assert_equal(3, #decomposition[0x1EAD], "fully expanded")
  self:assert_nil(decomposition[0xAC00], "Hangul syllables are algorithmic")
  self:assert_equal(0xC0, composition[0x41][0x300])
  for _, row in pairs(composition) do
    for _, composite in pairs(row) do
      self:assert_true(composite ~= 0x2126 and composite ~= 0x212B, "a singleton is never a primary composite")
    end
  end
  self:assert_nil(composition[0x308] and composition[0x308][0x301], "the exclusion U+0344 is not composed")
end

function T:test_every_composite_expands_back_to_its_pair()
  local decomposition, composition = data.load("decomposition"), data.load("composition")
  for first, row in pairs(composition) do
    for second, composite in pairs(row) do
      local expanded = decomposition[composite]
      self:assert_true(expanded ~= nil, ("%04X has a decomposition"):format(composite))
      local expected = {}
      for _, part in ipairs(decomposition[first] or { first }) do expected[#expected + 1] = part end
      expected[#expected + 1] = second
      self:assert_equal(table.concat(expected, ","), table.concat(expanded, ","), ("%04X"):format(composite))
    end
  end
end

return T
