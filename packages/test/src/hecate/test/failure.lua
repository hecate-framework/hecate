-- Assertion failures: the error class a failed assertion raises (xUnit: a test fails when an
-- assertion fails and errs when anything else is raised; Meszaros 2007, "Test Result Taxonomy").
global <const> require, debug, error

local core = require("hecate.core")

--- Raised by every assertion of `hecate.test.Case` that does not hold. The `context` carries
--- `location` (`file:line` of the assertion call in the test), and for comparisons `expected`,
--- `actual` and `differences` (a list of lines, one per structural difference).
---@class hecate.test.AssertionFailure : hecate.core.Error
local AssertionFailure = core.error_class("AssertionFailure", "hecate.test.AssertionFailure")

---@class hecate.test.failure
---@field AssertionFailure hecate.test.AssertionFailure
local M = { AssertionFailure = AssertionFailure }

--- Returns `file:line` of the innermost stack frame outside the sources of `hecate.test`
--- (the test that called the assertion), or nil when there is none.
---@param level? integer  first stack level to inspect, relative to the caller
---@return string?
function M.location(level)
  level = (level or 1) + 1
  while true do
    local info = debug.getinfo(level, "Sl")
    if info == nil then return nil end
    local source = info.short_src:gsub("\\", "/")
    if not source:find("/hecate/test/", 1, true) and info.what ~= "C" then
      return ("%s:%d"):format(info.short_src, info.currentline)
    end
    level = level + 1
  end
end

--- Raises an `AssertionFailure`.
---@param message string  what did not hold
---@param context? table  extra structured data (`expected`, `actual`, `differences`)
function M.fail(message, context)
  context = context or {}
  context.location = context.location or M.location(2)
  error(AssertionFailure({ message = message, context = context }), 0)
end

return M
