-- Raises errors of the hierarchy from the object model. The error module is loaded
-- lazily because it is itself built with the object model.
global <const> require, error

---@class hecate.core.internal.raise
local raise = {}

--- Raises a ConformanceError (composition, finalisation or lifecycle violation).
---@param message string
---@param context? table
function raise.conformance(message, context)
  local errors = require("hecate.core.error")
  error(errors.ConformanceError { message = message, context = context }, 0)
end

--- Raises an ArgumentError (a function of the object model was misused).
---@param message string
---@param context? table
function raise.argument(message, context)
  local errors = require("hecate.core.error")
  error(errors.ArgumentError { message = message, context = context }, 0)
end

return raise
