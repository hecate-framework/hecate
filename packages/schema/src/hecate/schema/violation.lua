-- A violation: one reason why a value does not conform to a schema (schemas-and-contracts.md, "Validation").
global <const> require, type, table, string

local core = require("hecate.core")

--- One violation found by validation: where (a JSON Pointer), what (a stable code) and why (a message).
---@class hecate.schema.Violation
---@field path string  JSON Pointer (RFC 6901) of the offending value inside the validated value; "" is the value itself
---@field code string  stable, machine-readable identifier, for example "minimum" or "required"
---@field message string  human-readable description; never contains the offending value
---@field context table  structured data about the constraint, for example `{ minimum = 1 }`
---@overload fun(path: string, code: string, message: string, context?: table): hecate.schema.Violation
local Violation = core.value_class("Violation")

---@param path string
---@param code string
---@param message string
---@param context? table
function Violation:init(path, code, message, context)
  self.path, self.code, self.message, self.context = path, code, message, context or {}
end

--- Renders the violation as `path: code: message` (the root path is shown as the empty pointer, `""`).
---@return string
function Violation:__tostring()
  return ("%s: %s: %s"):format(self.path == "" and '""' or self.path, self.code, self.message)
end

core.finalise(Violation)

--- Escapes one reference token of a JSON Pointer (RFC 6901 section 3: `~` becomes `~0`, then `/` becomes `~1`).
---@param token string
---@return string
local function escape_token(token)
  return (token:gsub("~", "~0"):gsub("/", "~1"))
end

return { Violation = Violation, escape_token = escape_token }
