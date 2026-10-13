-- Mutex: mutual exclusion lock (Dijkstra 1965), a binary semaphore with the same FIFO,
-- cancellation-safe hand-off. It has no owner: the permit may be released from any
-- coroutine, but normally is closed by the one that took it.
global <const> require

local core = require("hecate.core")
local Semaphore = require("hecate.reactor.semaphore")

---@class hecate.reactor.Mutex
---@overload fun(): hecate.reactor.Mutex
local Mutex = core.class("Mutex")

--- Creates an unlocked mutex.
function Mutex:init()
  self._semaphore = Semaphore(1)
end

--- Locks the mutex, suspending in FIFO order while it is held. The permit unlocks it when
--- released or closed: `local permit <close> = mutex:lock()`.
---@async
---@return hecate.reactor.Permit
function Mutex:lock()
  return self._semaphore:acquire()
end

--- Locks the mutex without suspending; returns nil when it is held.
---@return hecate.reactor.Permit?
function Mutex:try_lock()
  return self._semaphore:try_acquire()
end

--- Returns whether the mutex is held.
---@return boolean
function Mutex:is_locked() return self._semaphore:available() == 0 end

--- Returns the number of coroutines queued for the mutex.
---@return integer
function Mutex:waiting() return self._semaphore:waiting() end

---@param uncancellable boolean
---@return hecate.reactor.Permit
---@private
function Mutex:_lock(uncancellable)
  ---@diagnostic disable-next-line: invisible  -- friend class
  return self._semaphore:_acquire(uncancellable)
end

return core.finalise(Mutex)
