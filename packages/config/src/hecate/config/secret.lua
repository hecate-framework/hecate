-- The fallback secret object of `hecate.config` (configuration.md, "Secrets"): the same interface as `hecate.log.Secret`,
-- used when `hecate.log` is not loaded and no `secret` option is given (config cannot depend on log, layering).
global <const> require

local core = require("hecate.core")

--- The text that stands for a secret in every rendering.
local REDACTED = "[redacted]"

--- A value that renders as `[redacted]`; the value is reachable only through `reveal`.
---@class hecate.config.Secret
---@overload fun(value: any): hecate.config.Secret
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
