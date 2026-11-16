local core = require("hecate.core")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("CaseTest")

function T:test_a_case_is_a_class_named_after_its_argument()
  local class = hecate_test.Case("Sample")
  self:assert_true(core.is_class(class))
  self:assert_equal("Sample", core.name(class))
  self:assert_true(hecate_test.is_case(class))
  self:assert_false(hecate_test.is_case({}))
  self:assert_false(hecate_test.is_case(core.class("Other")))
end

function T:test_the_class_accepts_methods_until_it_is_finalised()
  local class = hecate_test.Case("Sample")
  function class:test_one() end
  core.finalise(class)
  self:assert_error(function() class.test_two = function() end end, { class = core.ConformanceError })
end

function T:test_a_case_can_extend_another_case()
  local parent = hecate_test.Case("Parent")
  function parent:test_inherited() end
  core.finalise(parent)
  local child = core.class("Child", parent)
  function child:test_own() end
  core.finalise(child)
  self:assert_true(hecate_test.is_case(child))
  local names = require("hecate.test.case").test_names(child)
  self:assert_equal({ "test_inherited", "test_own" }, names)
end

return require("hecate.core").finalise(T)
