-- The error hierarchy rooted at `hecate.core.Error` (object-model.md, "Errors";
-- ADR 0018). Failures raise instances of these classes; expected absence returns nil.
global <const> type, tostring, pairs, debug, table, require

local class_module = require("hecate.core.class")
local introspection = require("hecate.core.introspection")
local raise = require("hecate.core.internal.raise")
local validate = require("hecate.core.internal.validate")

local MAX_CHAIN = 32

local debug_mode = false

--- The root of the error hierarchy: failures raise instances of its subclasses, each with a stable `code`, a `message`, an optional `cause` and structured `context` (ADR 0018).
---@class hecate.core.Error
---@field message string  human-readable description; never exposed over HTTP by default
---@field code string  stable identifier, for example "hecate.http.FieldTooLargeError"
---@field cause? any  the error that caused this one (usually another Error)
---@field context table  structured data about the failure
---@field traceback? string  captured at creation when debug mode is on
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.Error
local Error = class_module.class("Error")

--- The fields an error is created from.
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
  if type(fields) ~= "table" then
    raise.argument("an error is created from a message string or a table of fields, got " .. type(fields))
  end
  if fields.message ~= nil and type(fields.message) ~= "string" then
    raise.argument("error message must be a string, got " .. type(fields.message))
  end
  if fields.code ~= nil and type(fields.code) ~= "string" then
    raise.argument("error code must be a string, got " .. type(fields.code))
  end
  if fields.context ~= nil and type(fields.context) ~= "table" then
    raise.argument("error context must be a table, got " .. type(fields.context))
  end
  self.message = fields.message or introspection.name(self)
  if fields.code ~= nil then self.code = fields.code end
  self.cause = fields.cause
  self.context = fields.context or {}
  if debug_mode then
    -- Start the traceback at the code that created the error: skip the frames of this library
    -- (this `init`, the class `__call`, an `init` of a subclass that delegates to this one).
    local level = 2
    while true do
      local info = debug.getinfo(level, "S")
      if info == nil or not info.short_src:find("hecate[/\\]core[/\\]") then break end
      level = level + 1
    end
    self.traceback = debug.traceback(self.message, level)
  end
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

-- The functions of this table are documented on `hecate.core` (module class completed here so
-- that the LuaLS export lists them; coding-standards.md, "Annotations for the reference").

---@class hecate.core
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
local errors = { Error = Error }

--- Returns true when `candidate` is `Error` or one of its subclasses.
---@param candidate any
---@return boolean
local function is_error_class(candidate)
  if not introspection.is_class(candidate) then return false end
  local current = candidate
  while current ~= nil do
    if current == Error then return true end
    current = introspection.superclass(current)
  end
  return false
end

--- Declares a finalised subclass of `Error` with a stable code.
---
--- Raises `hecate.core.ArgumentError` if `name` or `code` is not a non-empty string, or if
--- `superclass` is not `Error` or one of its subclasses.
---@param name string  class name
---@param code string  stable identifier, for example "hecate.http.FieldTooLargeError"
---@param superclass? any  `Error` or one of its subclasses; defaults to `Error`
---@return any class  the new error class
function errors.error_class(name, code, superclass)
  validate.name("error class", name)
  validate.name("error class code", code)
  if superclass ~= nil and not is_error_class(superclass) then
    raise.argument(("error class %s: superclass must be Error or one of its subclasses"):format(name))
  end
  local subclass = class_module.class(name, superclass or Error)
  subclass.code = code
  return class_module.finalise(subclass)
end

local error_class = errors.error_class

--- Raised when a configuration is invalid.
---@class hecate.core.ConfigurationError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ConfigurationError
errors.ConfigurationError = error_class("ConfigurationError", "hecate.core.ConfigurationError")
--- Raised when a class, trait or interface declaration is inconsistent, or a finalised class or an immutable value is modified.
---@class hecate.core.ConformanceError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ConformanceError
errors.ConformanceError = error_class("ConformanceError", "hecate.core.ConformanceError")
--- Raised when the caller broke the contract of an operation (a programmer error; Meyer, Design
--- by Contract). Base class of `ArgumentError` and `StateError` (OQ-77).
---@class hecate.core.PreconditionError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.PreconditionError
errors.PreconditionError = error_class("PreconditionError", "hecate.core.PreconditionError")
--- Raised when a function is called with an invalid argument (a programmer error).
---@class hecate.core.ArgumentError : hecate.core.PreconditionError
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ArgumentError
errors.ArgumentError = error_class("ArgumentError", "hecate.core.ArgumentError", errors.PreconditionError)
--- Raised when an operation is not allowed in the current state of the object: closed, already
--- serving, not booted (a programmer error).
---@class hecate.core.StateError : hecate.core.PreconditionError
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.StateError
errors.StateError = error_class("StateError", "hecate.core.StateError", errors.PreconditionError)
--- Raised in a computation that was cancelled, at its next suspension point.
---@class hecate.core.CancellationError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.CancellationError
errors.CancellationError = error_class("CancellationError", "hecate.core.CancellationError")
--- Raised when a deadline expires before the computation it bounds finishes.
---@class hecate.core.DeadlineExceededError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.DeadlineExceededError
errors.DeadlineExceededError = error_class("DeadlineExceededError", "hecate.core.DeadlineExceededError")
--- Raised when a suspending function is called outside a coroutine managed by the reactor.
---@class hecate.core.NonYieldableContextError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.NonYieldableContextError
errors.NonYieldableContextError = error_class("NonYieldableContextError", "hecate.core.NonYieldableContextError")
--- Raised when a channel is used after it was closed, or closed while a coroutine waited on it.
---@class hecate.core.ClosedChannelError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ClosedChannelError
errors.ClosedChannelError = error_class("ClosedChannelError", "hecate.core.ClosedChannelError")
--- The failures of a network transport, such as a refused or reset connection.
---@class hecate.core.NetworkError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.NetworkError
errors.NetworkError = error_class("NetworkError", "hecate.core.NetworkError")
--- The failures of the file system and of child processes. Base class of `hecate.reactor.IoError`;
--- a sibling of `NetworkError`, not a subclass of it (OQ-26 (2), OQ-32 (5)).
---@class hecate.core.IoError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.IoError
errors.IoError = error_class("IoError", "hecate.core.IoError")
--- Raised when a peer breaks the protocol that is being spoken.
---@class hecate.core.ProtocolError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ProtocolError
errors.ProtocolError = error_class("ProtocolError", "hecate.core.ProtocolError")
--- Raised when a value is rejected by validation.
---@class hecate.core.ValidationError : hecate.core.Error
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.core.ValidationError
errors.ValidationError = error_class("ValidationError", "hecate.core.ValidationError")

--- The failures reported by a database, with the SQLSTATE when the server provides one.
---@class hecate.core.DatabaseError : hecate.core.Error
---@overload fun(fields: hecate.core.DatabaseErrorFields|string, extra?: hecate.core.DatabaseErrorFields): hecate.core.DatabaseError
---@field sqlstate? string  SQLSTATE class and subclass (five characters) when available
local DatabaseError = class_module.class("DatabaseError", Error)
DatabaseError.code = "hecate.core.DatabaseError"

--- The fields a database error is created from.
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
---@param enabled boolean  `true` captures a traceback in every new error
function errors.set_debug_mode(enabled) debug_mode = enabled == true end

--- Returns whether tracebacks are captured on error creation.
---@return boolean enabled  `true` when debug mode is on
function errors.is_debug_mode() return debug_mode end

return errors
