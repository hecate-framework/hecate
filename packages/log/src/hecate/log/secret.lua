-- A value that is never rendered by a sink (invariant of `hecate.log`).
global <const> require, rawequal

local core = require("hecate.core")

--- The text that stands for a secret in every rendering.
local REDACTED = "[redacted]"

--- The protected values, keyed by secret object: private to this module and weak-keyed, so that a secret holds no field
--- that could be read or replaced, and a dropped secret releases its value.
local protected = core.weak_table("k")

--- A value marked as secret: a sink renders `[redacted]` in its place, at any depth of a
--- record. The value is reachable only through `reveal`. A secret is immutable (a value class of `hecate.core`, compared
--- by identity): a write raises `hecate.core.ConformanceError`, so the value cannot be replaced.
---@class hecate.log.Secret
---@overload fun(value: any): hecate.log.Secret
local Secret = core.value_class("Secret")

--- Initialises a secret around a value.
---@param value any  the value to protect
function Secret:init(value)
  protected[self] = { value = value }
end

--- Returns the protected value.
---@return any value
function Secret:reveal() return protected[self].value end

--- Returns the redaction text, never the value.
---@return string
function Secret:__tostring() return REDACTED end

--- Identity, not the structural equality of value classes: two secrets are equal only when they are the same object
--- (a comparison never tells anything about the protected values).
---@param other any
---@return boolean
function Secret:__eq(other) return rawequal(self, other) end

Secret.REDACTED = REDACTED

return core.finalise(Secret)
