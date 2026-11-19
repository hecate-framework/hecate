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

function T:test_the_dependencies_of_a_readme_cell_carry_an_optional_minimum()
  local deps = rockspec.readme_dependencies("[`core`](../core), [`unicode-data`](../unicode-data) (>= 18.0.0), [`json`](../json)")
  self:assert_equal(3, #deps)
  self:assert_equal("core", deps[1].name)
  self:assert_nil(deps[1].minimum)
  self:assert_equal("unicode-data", deps[2].name)
  self:assert_equal("18.0.0", deps[2].minimum)
  self:assert_nil(deps[3].minimum)
  self:assert_equal('"hecate-unicode-data >= 18.0.0"', rockspec.dependency_string(deps[2]))
  self:assert_equal('"hecate-core"', rockspec.dependency_string(deps[1]))
  self:assert_equal(0, #rockspec.readme_dependencies("none"))
end

function T:test_the_licence_follows_the_package()
  self:assert_equal("MIT", rockspec.license("core"))
  self:assert_equal("Unicode-3.0", rockspec.license("unicode-data"))
end

function T:test_a_dependency_is_constrained_by_a_lower_bound_only()
  local function spec(dep) return ('\ndependencies = {\n  "lua >= 5.5, < 5.6",\n  "%s",\n}\n'):format(dep) end
  self:assert_equal(0, #rockspec.constraint_problems("r", spec("hecate-unicode-data >= 18.0.0")))
  self:assert_equal(0, #rockspec.constraint_problems("r", spec("hecate-core")))
  for _, bad in ipairs({ "hecate-unicode-data == 18.0.0", "hecate-unicode-data >= 18.0.0, < 19", "hecate-core ~> 1.0", "hecate-core < 2.0.0" }) do
    self:assert_equal(1, #rockspec.constraint_problems("r", spec(bad)), bad)
  end
end

function T:test_the_data_rock_is_versioned_by_the_unicode_version()
  self:assert_nil(rockspec.version_problem("unicode-data", "scm-1", "0.1.0", "18.0.0"))
  self:assert_nil(rockspec.version_problem("unicode-data", "18.0.0-1", "0.1.0", "18.0.0"))
  self:assert_nil(rockspec.version_problem("unicode-data", "18.0.0-2", "0.1.0", "18.0.0"))
  self:assert_not_nil(rockspec.version_problem("unicode-data", "0.1.0-1", "0.1.0", "18.0.0"))
  self:assert_nil(rockspec.version_problem("core", "0.1.0-1", "0.1.0", "18.0.0"))
  self:assert_not_nil(rockspec.version_problem("core", "18.0.0-1", "0.1.0", "18.0.0"))
end

return T
