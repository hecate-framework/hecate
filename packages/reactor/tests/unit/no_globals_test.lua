local test = require("harness.test")
local T = test.Case("NoGlobalsTest")

function T:test_requiring_the_package_defines_no_globals()
  local before = {}
  for k in pairs(_G) do before[k] = true end
  for name in pairs(package.loaded) do
    if name:find("^hecate%.reactor") then package.loaded[name] = nil end
  end
  require("hecate.reactor")
  for k in pairs(_G) do self:assert_true(before[k], "new global: " .. tostring(k)) end
end

return T
