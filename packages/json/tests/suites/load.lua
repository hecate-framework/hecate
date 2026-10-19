-- Loads a shared suite for one backend. The native backend must be built (`lua tools/run.lua build-native
-- json`); where it is not, the suite reports one skipped case, except in CI (CI=true) on POSIX, where a missing
-- native module is a failure: a pipeline must never go green without having exercised it.
local test = require("harness.test")
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local M = {}

---@param suite string  file name in tests/suites without extension
---@param backend_name "reference"|"native"
function M.load(suite, backend_name)
  if backend_name == "native" and not pcall(require, "hecate.json.native") then
    local T = test.Case("JsonNative[" .. suite .. "]")
    function T:test_native_module_is_built()
      if (os.getenv("CI") and package.config:sub(1, 1) == "/") then self:fail("hecate.json.native is not built (lua tools/run.lua build-native json)") end
      io.stderr:write("# skipped: hecate.json.native is not built (lua tools/run.lua build-native json)\n")
    end
    return T
  end
  return assert(loadfile(here .. "/" .. suite .. ".lua"))(backend_name)
end

return M
