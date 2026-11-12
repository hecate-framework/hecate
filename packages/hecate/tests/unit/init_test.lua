local test = require("harness.test")
local hecate = require("hecate")
local kernel = require("hecate.kernel")
local T = test.Case("HecateMetaModuleTest")

--- The framework surface of the meta-module, each name with the source it re-exports.
local EXPECTED = {
  "Application", "Controller", "routes", "respond", "problem", "load_configuration",
  "RouteDeclarationError", "ModuleError", "SupervisorError",
}

function T:test_each_re_export_is_the_value_of_its_source()
  for _, name in ipairs(EXPECTED) do
    self:assert_true(hecate[name] ~= nil, name .. " is missing")
    self:assert_equal(kernel[name], hecate[name], name)
  end
end

function T:test_no_extra_key_leaks()
  local expected = {}
  for _, name in ipairs(EXPECTED) do expected[name] = true end
  for key in pairs(hecate) do
    self:assert_true(expected[key] == true, "unexpected key " .. tostring(key))
  end
end

function T:test_object_model_entry_points_are_not_re_exported()
  -- OQ-57: applications use `core.class` and `core.finalise` from `hecate.core`.
  for _, name in ipairs { "class", "trait", "interface", "finalise" } do
    self:assert_nil(hecate[name], name)
  end
end

function T:test_problem_classes_are_reachable()
  self:assert_equal(kernel.problem.NotFound, hecate.problem.NotFound)
  self:assert_equal(kernel.problem.define, hecate.problem.define)
end

return T
