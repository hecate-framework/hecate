local test = require("harness.test")
local core = require("hecate.core")
local unicode = require("hecate.unicode")
local tables = require("hecate.unicode.internal.tables")
local T = test.Case("UnicodeTablesTest")

local function fake(format)
  return { unicode_version = "99.0.0", format = format, load = function() error("must not load a table of a format it does not know") end }
end

function T:test_a_layout_it_does_not_know_is_refused_before_any_table_is_read()
  for _, format in ipairs({ 0, 2, 99, "1", false }) do
    local err = self:assert_error(function() tables.load(fake(format)) end)
    self:assert_true(core.is_instance_of(err, unicode.DataFormatError), tostring(format))
    self:assert_true(core.is_instance_of(err, unicode.UnicodeError))
    self:assert_equal("hecate.unicode.DataFormatError", err.code)
    self:assert_equal(format, err.context.format)
    self:assert_equal("99.0.0", err.context.unicode_version)
    self:assert_true(err.message:find("hecate-unicode-data", 1, true) ~= nil, "the message names the rock")
  end
end

function T:test_the_installed_data_has_a_supported_layout_and_expands_to_lookups()
  local loaded = tables.get()
  self:assert_equal(230, loaded.combining_class[0x301])
  self:assert_equal(220, loaded.combining_class[0x323])
  self:assert_equal(1, loaded.combining_class[0x334])
  self:assert_nil(loaded.combining_class[0x41])
  self:assert_equal(2, #loaded.decomposition[0xC0])
  self:assert_equal(0xC0, loaded.composition[0x41][0x300])
  self:assert_true(tables.get() == loaded, "loaded once")
end

return T
