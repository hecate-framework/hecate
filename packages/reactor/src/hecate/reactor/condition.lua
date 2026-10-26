-- Condition: condition variable attached to a Monitor (Hoare 1974). See `monitor.lua` for
-- the signalling discipline.
global <const> error, pcall, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Waitq = require("hecate.reactor.internal.waitq")

--- A condition variable: coroutines wait on it inside a monitor until another coroutine signals.
---@class hecate.reactor.Condition
---@overload fun(monitor: hecate.reactor.Monitor): hecate.reactor.Condition
local Condition = core.class("Condition")

--- Creates a condition attached to `monitor`; prefer `Monitor:condition()`.
---@param monitor hecate.reactor.Monitor
function Condition:init(monitor)
  if not core.is_instance_of(monitor, require("hecate.reactor.monitor")) then -- lazy: monitor requires condition
    error(core.ArgumentError("reactor.Condition: expects a Monitor"), 2)
  end
  self._monitor = monitor
  self._waiters = Waitq()
end

--- Requires the running coroutine to be inside the monitor.
---@param operation string
---@return table task
local function require_inside(self, operation)
  local task = context.current_task(operation)
  if self._monitor._owner ~= task then
    error(core.ArgumentError("reactor." .. operation .. ": requires the calling coroutine to have entered the monitor"), 3)
  end
  return task
end

--- Leaves the monitor, suspends until signalled, and re-enters the monitor. Must be called
--- inside the monitor and inside a loop that tests the awaited predicate.
---@async
function Condition:wait()
  local task = require_inside(self, "Condition:wait")
  local monitor, waiters = self._monitor, self._waiters
  ---@diagnostic disable-next-line: invisible
  monitor:_leave()
  local waiter
  local ok, err = pcall(context.suspend, function(wake)
    waiter = waiters:push({ wake = wake })
    return function() waiters:remove(waiter) end
  end)
  ---@diagnostic disable-next-line: invisible
  monitor:_reenter(task)
  if not ok then error(err, 0) end
end

--- Wakes the first waiting coroutine, if any. Must be called inside the monitor.
function Condition:signal()
  require_inside(self, "Condition:signal")
  self._waiters:wake_first(true)
end

--- Wakes every waiting coroutine. Must be called inside the monitor.
function Condition:broadcast()
  require_inside(self, "Condition:broadcast")
  while self._waiters:wake_first(true) do end
end

--- Returns the number of coroutines waiting on the condition.
---@return integer
function Condition:waiting() return self._waiters.size end

return core.finalise(Condition)
