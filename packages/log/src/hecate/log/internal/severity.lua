-- Helpers on severities shared by the logger and the sinks (not public API).
global <const> require, type, tostring, error, table

local core = require("hecate.core")
local Severity = require("hecate.log.severity")

local M = {}

--- Returns the RFC 5424 numerical code (0 to 7) of a severity.
---@param severity hecate.core.EnumerationValue
---@return integer
function M.code(severity) return severity.ordinal - 1 end

--- Returns the severity named by a name or given as a value.
---
--- Raises `hecate.core.ArgumentError` if the argument is neither.
---@param value any
---@param level integer  stack level of the caller to blame
---@return hecate.core.EnumerationValue
function M.resolve(value, level)
  if Severity:contains(value) then return value end
  local found = type(value) == "string" and Severity:find(value) or nil
  if found == nil then
    error(core.ArgumentError(("invalid severity %s: expected one of %s"):format(
      type(value) == "string" and ("%q"):format(value) or tostring(value), table.concat(Severity:names(), ", "))),
      level + 1)
  end
  return found
end

return M
