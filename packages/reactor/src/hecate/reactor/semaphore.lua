-- Semaphore: counting synchronisation primitive (Dijkstra 1965, P and V). Waiters are served
-- in FIFO order by direct hand-off: a released unit goes to the first live waiter instead of
-- being added to the count, so a newcomer cannot overtake a waiter (no barging, no
-- starvation) and a cancelled waiter never swallows a unit (it is withdrawn, and a hand-off
-- to a waiter whose suspension already ended is skipped).
-- Invariant: live waiters exist only while the count is zero.
global <const> math, error, require, tostring

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Waitq = require("hecate.reactor.internal.waitq")
local Permit = require("hecate.reactor.permit")

--- A counting semaphore for coroutines of one reactor.
---@class hecate.reactor.Semaphore
---@overload fun(units: integer): hecate.reactor.Semaphore
local Semaphore = core.class("Semaphore")

--- Creates a semaphore holding `units` units.
---@param units integer  not negative
function Semaphore:init(units)
  if math.type(units) ~= "integer" or units < 0 then
    error(core.ArgumentError(("reactor.Semaphore: expects a non-negative integer, got %s"):format(tostring(units))), 2)
  end
  self._count = units
  self._waiters = Waitq()
end

--- Takes one unit, suspending in FIFO order while none is available. The returned permit
--- gives the unit back when released or closed.
---@async
---@return hecate.reactor.Permit
function Semaphore:acquire()
  return self:_acquire(false)
end

--- Takes one unit without suspending; returns nil when none is available.
---@return hecate.reactor.Permit?
function Semaphore:try_acquire()
  if self._count == 0 then return nil end
  self._count = self._count - 1
  return Permit(function() self:release() end)
end

--- Adds one unit (Dijkstra's V): hands it to the first waiter, if any. Never suspends.
--- Units added this way are not tied to a permit.
function Semaphore:release()
  if not self._waiters:wake_first(true) then self._count = self._count + 1 end
end

--- Returns the number of units available now.
---@return integer
function Semaphore:available() return self._count end

--- Returns the number of coroutines queued for a unit.
---@return integer
function Semaphore:waiting() return self._waiters.size end

---@param uncancellable boolean  true to wait even if cancelled (used to restore a lock)
---@return hecate.reactor.Permit
---@private
function Semaphore:_acquire(uncancellable)
  context.current_computation("Semaphore:acquire")
  if self._count > 0 then
    self._count = self._count - 1
  else
    local waiters = self._waiters
    local waiter
    context.suspend(function(wake)
      waiter = waiters:push({ wake = wake })
      return function() waiters:remove(waiter) end
    end, uncancellable)
  end
  return Permit(function() self:release() end)
end

return core.finalise(Semaphore)
