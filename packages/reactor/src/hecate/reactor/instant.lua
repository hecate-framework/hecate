-- An absolute point on the reactor clock, accepted by `deadline` (concurrency.md,
-- "Primitives"). A plain number given to `deadline` is a relative duration instead.
global <const> type, error, tostring, require

local core = require("hecate.core")

--- A point on the reactor clock, in seconds, used as an absolute deadline.
---@class hecate.reactor.Instant
---@field seconds number  position on the reactor clock, in seconds (see `Reactor:now`)
---@overload fun(seconds: number): hecate.reactor.Instant
local Instant = core.class("Instant")

--- Initialises an instant.
---@param seconds number
function Instant:init(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds then
    error(core.ArgumentError(("invalid instant %s: expected a number of seconds"):format(tostring(seconds))), 2)
  end
  self.seconds = seconds
end

return core.finalise(Instant)
