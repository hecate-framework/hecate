local test = require("harness.test")
local T = test.Case("NoGlobalsTest")

function T:test_requiring_the_package_defines_no_globals_and_has_no_side_effects()
  local before = {}
  for key in pairs(_G) do before[key] = true end
  for name in pairs(package.loaded) do
    if name:find("^hecate%.doc") then package.loaded[name] = nil end
  end
  local doc = require("hecate.doc")
  for key in pairs(_G) do self:assert_true(before[key], "new global: " .. tostring(key)) end
  self:assert_equal("function", type(doc.build))
  self:assert_equal("function", type(doc.markdown.render))
end

return T
