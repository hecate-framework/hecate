local test = require("harness.test")
local rockspec = require("lib.rockspec")
local T = test.Case("RockspecTest")

local GENERATED = 'package = "hecate-x"\n\ndependencies = {\n  "lua >= 5.5, < 5.6",\n}\n\nbuild = {\n  type = "builtin",\n  modules = {},\n}\n'
local CUSTOM = 'build = {\n  type = "builtin",\n  modules = { ["hecate.x"] = "src/hecate/x/init.lua" },\n  install = { lib = { ["hecate.x.native"] = "native.so" } },\n}\n'

function T:test_the_default_build_is_kept_when_nothing_was_edited()
  self:assert_equal(GENERATED, rockspec.keep_build(GENERATED, GENERATED))
  self:assert_equal(GENERATED, rockspec.keep_build(GENERATED, nil))
end

function T:test_a_hand_made_build_survives_regeneration()
  local merged = rockspec.keep_build(GENERATED, 'package = "old"\n\n' .. CUSTOM)
  self:assert_true(merged:find('install = { lib', 1, true) ~= nil)
  self:assert_true(merged:find('package = "hecate-x"', 1, true) ~= nil, "the rest is regenerated")
  self:assert_nil(merged:find("modules = {},", 1, true))
end

function T:test_the_build_block_is_found_with_nested_braces()
  self:assert_equal(CUSTOM:match("(%b{})"), rockspec.build_block("x\n" .. CUSTOM))
end

return T
