local core = require("hecate.core")
local reactor = require("hecate.reactor")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("DiscoveryTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local fixtures = here .. "/../fixtures/discovery"

function T:test_finds_test_files_recursively_in_sorted_order()
  local paths = reactor.run(hecate_test.discover, fixtures)
  local names = {}
  for i, p in ipairs(paths) do names[i] = p:sub(#fixtures + 2) end
  self:assert_equal({ "a_test.lua", "nested/b_test.lua" }, names)
end

function T:test_a_missing_directory_yields_no_files()
  self:assert_equal({}, reactor.run(hecate_test.discover, fixtures .. "/missing"))
end

function T:test_load_returns_the_case_of_a_file()
  local case = hecate_test.load(fixtures .. "/a_test.lua")
  self:assert_equal("FixtureA", core.name(case))
  local summary = hecate_test.Runner():run({ case })
  self:assert_true(summary.ok)
end

function T:test_load_rejects_files_that_are_not_cases()
  self:assert_error(function() hecate_test.load(fixtures .. "/../discovery_bad/not_a_case.lua") end,
    { class = hecate_test.LoadError, pattern = "does not return a test case" })
  self:assert_error(function() hecate_test.load(fixtures .. "/../discovery_bad/raises.lua") end,
    { class = hecate_test.LoadError, pattern = "raised" })
  self:assert_error(function() hecate_test.load(fixtures .. "/nope.lua") end, { class = hecate_test.LoadError })
end

return require("hecate.core").finalise(T)
