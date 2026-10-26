-- Future: placeholder for the value of a concurrent computation (glossary: future;
-- Baker and Hewitt 1977). Created by `fork`; settled by the scheduler.
global <const> table, error, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")

---@alias hecate.reactor.FutureState "pending"|"completed"|"failed"|"cancelled"

--- The placeholder for the value of a concurrent computation, created by `fork` and settled by the scheduler.
---@class hecate.reactor.Future
---@overload fun(): hecate.reactor.Future
local Future = core.class("Future")

--- Initialises a pending future.
function Future:init()
  self._state = "pending"
  self._results = nil
  self._error = nil
  self._computation = nil
  self._watchers = {}
end

--- Returns the state: `pending`, `completed`, `failed` or `cancelled`.
---@return hecate.reactor.FutureState
function Future:state() return self._state end

--- Returns whether the computation has finished, whatever the outcome.
---@return boolean
function Future:done() return self._state ~= "pending" end

--- Waits until the future is done and returns the values of the computation. Raises the
--- error of a failed computation, or a `CancellationError` if it was cancelled.
---@async
---@return any ...
function Future:value()
  if self._state == "pending" then
    context.suspend(function(wake)
      local watcher = self:_watch(wake)
      return function() watcher.active = false end
    end)
  end
  if self._state == "completed" then
    local results = self._results --[[@as table]]
    return table.unpack(results, 1, results.n)
  end
  error(self._error, 0)
end

--- Requests cancellation of the computation (cooperative: delivered as a
--- `CancellationError` at its next suspension point). Returns false if already done.
---@return boolean requested
function Future:cancel()
  if self._state ~= "pending" then return false end
  local err = core.CancellationError({ message = "future cancelled", context = { source = self } })
  if self._computation then
    context.cancel_computation(self._computation, err)
  else
    self:_settle("cancelled", nil, err)
  end
  return true
end

--- Registers a wake-up called (in order) when the future settles.
---@param wake fun(): boolean
---@return table watcher  set `active = false` to withdraw
---@private
function Future:_watch(wake)
  local watcher = { wake = wake, active = true }
  self._watchers[#self._watchers + 1] = watcher
  return watcher
end

--- Settles the future and wakes its watchers. Called by the scheduler only.
---@param state "completed"|"failed"|"cancelled"
---@param results? table  packed results when completed
---@param err? any
---@private
function Future:_settle(state, results, err)
  if self._state ~= "pending" then return end
  self._state, self._results, self._error = state, results, err
  local watchers = self._watchers
  self._watchers = {}
  for i = 1, #watchers do
    local watcher = watchers[i]
    if watcher.active then watcher.wake() end
  end
end

return core.finalise(Future)
