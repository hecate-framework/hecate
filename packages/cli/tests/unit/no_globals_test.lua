local test = require("harness.test")
local T = test.Case("CliNoGlobalsTest")

function T:test_requiring_the_package_defines_no_globals()
  local before = {}
  for key in pairs(_G) do before[key] = true end
  for name in pairs(package.loaded) do
    if name:find("^hecate%.cli") then package.loaded[name] = nil end
  end
  local cli = require("hecate.cli")
  for key in pairs(_G) do self:assert_true(before[key], "new global: " .. tostring(key)) end
  self:assert_equal("function", type(cli.run))
end

return T
