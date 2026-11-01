-- Argument checks shared by the declaration functions of the object model, so that classes,
-- traits, interfaces, enumerations and error classes accept the same names and report the
-- same messages (ADR 0018: a misused function raises `ArgumentError`).
global <const> type, next, require

local raise = require("hecate.core.internal.raise")

---@class hecate.core.internal.validate
local validate = {}

--- Checks that a name (or a code) is a non-empty string.
---@param kind string  what is named, for the message: "class", "trait", "interface", ...
---@param value any  the candidate name
---@return string name  `value`, now known to be a non-empty string
function validate.name(kind, value)
  if type(value) ~= "string" then
    raise.argument(("%s name must be a non-empty string, got %s"):format(kind, type(value)))
  elseif value == "" then
    raise.argument(("%s name must be a non-empty string, got an empty string"):format(kind))
  end
  return value
end

--- Returns true when `value` is a table whose only keys are the integers 1 to `#value`.
---@param value any
---@return boolean
function validate.is_sequence(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in next, value do
    if type(key) ~= "number" or key < 1 or key > #value or key % 1 ~= 0 then return false end
    count = count + 1
  end
  return count == #value
end

return validate
