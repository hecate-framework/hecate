-- A value that is never rendered by a sink (invariant of `hecate.log`).
global <const> require

local core = require("hecate.core")

--- The text that stands for a secret in every rendering.
local REDACTED = "[redacted]"

--- A value marked as secret: a sink renders `[redacted]` in its place, at any depth of a
--- record. The value is reachable only through `reveal`.
---@class hecate.log.Secret
---@overload fun(value: any): hecate.log.Secret
local Secret = core.class("Secret")

--- Initialises a secret around a value.
---@param value any  the value to protect
function Secret:init(value)
  self._reveal = function() return value end
end

--- Returns the protected value.
---@return any value
function Secret:reveal() return self._reveal() end

--- Returns the redaction text, never the value.
---@return string
function Secret:__tostring() return REDACTED end

Secret.REDACTED = REDACTED

return core.finalise(Secret)
