-- Monitor and Condition: a mutex with condition variables (Hoare 1974; Brinch Hansen 1973).
-- Discipline: a coroutine enters the monitor, tests its predicate in a loop and waits on a
-- condition; the wait leaves the monitor, suspends, and re-enters it before returning.
-- Signalling follows Mesa semantics (Lampson and Redell 1980): the signaller keeps the
-- monitor and the woken waiter re-enters behind the coroutines already queued, so a waiter
-- must re-test its predicate (OQ-25). A cancelled wait re-enters the monitor (uncancellably)
-- before raising, so the cleanup of the enclosing `<close>` permit runs inside the monitor.
global <const> error, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Condition = require("hecate.reactor.condition")
local Mutex = require("hecate.reactor.mutex")
local Permit = require("hecate.reactor.permit")

--- A monitor: mutual exclusion with condition variables (Hoare 1974).
---@class hecate.reactor.Monitor
---@overload fun(): hecate.reactor.Monitor
local Monitor = core.class("Monitor")

--- Creates an unoccupied monitor.
function Monitor:init()
  self._mutex = Mutex()
  self._owner = nil
  self._inner = nil
end

--- Enters the monitor, suspending in FIFO order while it is occupied. The permit leaves it
--- when released or closed: `local permit <close> = monitor:enter()`. Not reentrant.
---@async
---@return hecate.reactor.Permit
function Monitor:enter()
  local task = context.current_task("Monitor:enter")
  if self._owner == task then
    error(core.ArgumentError("the calling coroutine has already entered the monitor (not reentrant)"), 2)
  end
  self._inner = self._mutex:lock()
  self._owner = task
  return Permit(function()
    self._owner = nil
    self._inner:release()
  end)
end

--- Creates a condition variable attached to this monitor.
---@return hecate.reactor.Condition
function Monitor:condition()
  return Condition(self)
end

--- Returns whether a coroutine is inside the monitor.
---@return boolean
function Monitor:is_entered() return self._owner ~= nil end

--- Leaves the monitor on behalf of a waiting coroutine.
---@private
function Monitor:_leave()
  self._owner = nil
  self._inner:release()
end

--- Re-enters the monitor after a wait; not cancellable.
---@param task table
---@private
function Monitor:_reenter(task)
  ---@diagnostic disable-next-line: invisible  -- friend class
  self._inner = self._mutex:_lock(true)
  self._owner = task
end

return core.finalise(Monitor)
