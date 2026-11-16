-- Strings generated from the ECMA-262 form of a `pattern` (the subset `hecate.schema.pattern` emits).
global <const> require, ipairs, table, tostring

local core = require("hecate.core")
local pattern_text = require("hecate.test.pattern_text")
local schema = require("hecate.schema")
local hecate_test = require("hecate.test")

local T = hecate_test.Case("PatternTextTest")

-- A deterministic source: the same sequence each run.
local function source()
  local state = 12345
  return function(low, high)
    state = (state * 1103515245 + 12345) % 2147483648
    return low + state % (high - low + 1)
  end
end

function T:test_the_text_matches_the_lua_pattern_it_was_translated_from()
  for _, lua_pattern in ipairs({ "^%d+$", "^%a%a%d?$", "^[%w_]-x$", "^(%d%d)-%1$", "^[^%s]+$", "^%x*%.%x$", "%u%l" }) do
    local regex = schema.string({ pattern = lua_pattern }):to_json_schema().pattern
    local between = source()
    for _ = 1, 50 do
      local text = pattern_text.generate(regex, between)
      self:assert_true(text ~= nil and text:find(lua_pattern) ~= nil, lua_pattern .. " vs " .. tostring(text))
    end
  end
end

function T:test_the_length_bounds_are_respected_or_the_result_is_nil()
  local between = source()
  for _ = 1, 30 do
    local text = pattern_text.generate("^[0-9]*$", between, 5, 7)
    self:assert_true(text ~= nil and #text >= 5 and #text <= 7)
  end
  self:assert_nil(pattern_text.generate("^[0-9]$", between, 3, 4))
  self:assert_nil(pattern_text.generate("^[0-9]+$", between, 0, 0))
end

function T:test_only_ascii_is_produced_and_controls_only_when_asked_for()
  local between = source()
  for _ = 1, 50 do
    local text = pattern_text.generate("^[\\s\\S]+$", between)
    self:assert_true(text ~= nil and not text:find("[^\32-\126]"))
  end
  local controls = pattern_text.generate("^[\\x00-\\x1F\\x7F]+$", between)
  self:assert_true(controls ~= nil and controls:find("^[%c]+$") ~= nil)
end

function T:test_a_regular_expression_outside_the_subset_raises_argument_error()
  for _, regex in ipairs({ "(?=a)", "[a", "a\\", "(a", "a)", "[z-a]", "\\xZZ", "caf\195\169" }) do
    self:assert_error(function() pattern_text.generate(regex, source()) end, { class = core.ArgumentError })
  end
end

return core.finalise(T)
