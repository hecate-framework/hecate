-- The error hierarchy rooted at `hecate.core.Error` (object-model.md, "Errors";
-- ADR 0018). Failures raise instances of these classes; expected absence returns nil.
global <const> type, tostring, pairs, debug, table, require

local class_module = require("hecate.core.class")
local introspection = require("hecate.core.introspection")

local MAX_CHAIN = 32

local debug_mode = false

---@class hecate.core.Error
---@field message string  human-readable description; never exposed over HTTP by default
---@field code string  stable identifier, for example "hecate.http.HeaderTooLarge"
---@field cause? any  the error that caused this one (usually another Error)
---@field context table  structured data about the failure
---@field traceback? string  captured at creation when debug mode is on
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.Error
local Error = class_module.class("Error")

---@class hecate.core.ErrorFields
---@field message? string
---@field code? string  overrides the class code
---@field cause? any
---@field context? table

Error.code = "hecate.core.Error"

--- Initialises an error from a message string, or from a table of fields.
---@param fields hecate.core.ErrorFields|string
---@param extra? hecate.core.ErrorFields  further fields when `fields` is a message
function Error:init(fields, extra)
  if type(fields) == "string" then
    local merged = { message = fields }
    for key, value in pairs(extra or {}) do merged[key] = value end
    fields = merged
  end
  fields = fields or {}
  self.message = fields.message or introspection.name(self)
  if fields.code ~= nil then self.code = fields.code end
  self.cause = fields.cause
  self.context = fields.context or {}
  if debug_mode then self.traceback = debug.traceback(self.message, 2) end
end

--- Returns the deepest cause of this error, or the error itself when it has none.
---@return any
function Error:root_cause()
  local current = self
  for _ = 1, MAX_CHAIN do
    local next_cause = type(current) == "table" and current.cause or nil
    if next_cause == nil then break end
    current = next_cause
  end
  return current
end

--- Renders the error and its chain of causes, one per line.
---@return string
function Error:__tostring()
  ---@type any
  local current = self
  local lines = {}
  for depth = 1, MAX_CHAIN do
    local line
    if type(current) == "table" and introspection.is_instance_of(current, Error) then
      line = ("%s: %s"):format(current.code, current.message)
    else
      line = tostring(current)
    end
    lines[depth] = depth == 1 and line or ("caused by: " .. line)
    current = type(current) == "table" and current.cause or nil
    if current == nil then break end
  end
  return table.concat(lines, "\n")
end

class_module.finalise(Error)

--- Declares a finalised subclass of `Error` with a stable code.
---@param name string
---@param code string  stable identifier, for example "hecate.http.HeaderTooLarge"
---@param superclass? any  defaults to `Error`
---@return any
local function error_class(name, code, superclass)
  local subclass = class_module.class(name, superclass or Error)
  subclass.code = code
  return class_module.finalise(subclass)
end

local errors = { Error = Error, error_class = error_class }

---@class hecate.core.ConfigurationError : hecate.core.Error
errors.ConfigurationError = error_class("ConfigurationError", "hecate.core.ConfigurationError")
---@class hecate.core.ConformanceError : hecate.core.Error
errors.ConformanceError = error_class("ConformanceError", "hecate.core.ConformanceError")
---@class hecate.core.ArgumentError : hecate.core.Error
errors.ArgumentError = error_class("ArgumentError", "hecate.core.ArgumentError")
---@class hecate.core.CancellationError : hecate.core.Error
errors.CancellationError = error_class("CancellationError", "hecate.core.CancellationError")
---@class hecate.core.DeadlineExceededError : hecate.core.Error
errors.DeadlineExceededError = error_class("DeadlineExceededError", "hecate.core.DeadlineExceededError")
---@class hecate.core.NonYieldableContextError : hecate.core.Error
errors.NonYieldableContextError = error_class("NonYieldableContextError", "hecate.core.NonYieldableContextError")
---@class hecate.core.NetworkError : hecate.core.Error
errors.NetworkError = error_class("NetworkError", "hecate.core.NetworkError")
---@class hecate.core.ProtocolError : hecate.core.Error
errors.ProtocolError = error_class("ProtocolError", "hecate.core.ProtocolError")
---@class hecate.core.ValidationError : hecate.core.Error
errors.ValidationError = error_class("ValidationError", "hecate.core.ValidationError")

---@class hecate.core.DatabaseError : hecate.core.Error
---@field sqlstate? string  SQLSTATE class and subclass (five characters) when available
local DatabaseError = class_module.class("DatabaseError", Error)
DatabaseError.code = "hecate.core.DatabaseError"

---@class hecate.core.DatabaseErrorFields : hecate.core.ErrorFields
---@field sqlstate? string

---@param fields hecate.core.DatabaseErrorFields|string
---@param extra? hecate.core.DatabaseErrorFields
function DatabaseError:init(fields, extra)
  Error.init(self, fields, extra)
  local source = type(fields) == "table" and fields or extra
  self.sqlstate = source and source.sqlstate or nil
end

errors.DatabaseError = class_module.finalise(DatabaseError)

--- Turns capture of tracebacks on error creation on or off (debug mode).
---@param enabled boolean
function errors.set_debug_mode(enabled) debug_mode = enabled == true end

--- Returns whether tracebacks are captured on error creation.
---@return boolean
function errors.is_debug_mode() return debug_mode end

return errors
