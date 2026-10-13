-- Synchronisation primitives of concurrency.md, "Primitives": Channel (Hoare, CSP, 1978),
-- Semaphore and Mutex (Dijkstra 1965), Monitor and Condition (Hoare 1974; Brinch Hansen
-- 1973). Every blocking operation suspends through `context.suspend`, so it is cancellable
-- and raises `NonYieldableContextError` outside a managed coroutine. Waiters are served in
-- FIFO order. Conditions have Mesa semantics: a woken waiter re-checks its predicate.
global <const> type, error, math, tostring, coroutine, pcall, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")

local M = {}

-- A FIFO of waiters. An entry is `{ wake = fn, dead = bool, ... }`; a dead entry (its task
-- left the wait without being served) and a stale wake-up (returns false) are skipped.
local function queue_new() return { head = 1, tail = 0 } end

local function queue_push(q, entry)
  q.tail = q.tail + 1
  q[q.tail] = entry
end

--- Removes and returns the first entry that is still waiting, after calling `serve(entry)`
--- on it; `serve` returns whether the wake-up reached its task.
local function queue_serve(q, serve)
  while q.head <= q.tail do
    local entry = q[q.head]
    q[q.head] = nil
    q.head = q.head + 1
    if not entry.dead and serve(entry) then return entry end
  end
  q.head, q.tail = 1, 0
  return nil
end

local function queue_peek(q)
  while q.head <= q.tail do
    local entry = q[q.head]
    if not entry.dead then return entry end
    q[q.head] = nil
    q.head = q.head + 1
  end
  q.head, q.tail = 1, 0
  return nil
end

--- Suspends in `q` until served; `entry` carries the data the server needs.
local function wait_in(q, entry, uncancellable)
  return context.suspend(function(wake)
    entry.wake = wake
    queue_push(q, entry)
    return function() entry.dead = true end
  end, uncancellable)
end

-- Channel.

local CLOSED = {}

---@class hecate.reactor.Channel
---@overload fun(capacity?: integer): hecate.reactor.Channel
local Channel = core.class("Channel")

--- Creates a channel holding up to `capacity` values; 0 (default) is a rendezvous channel.
---@param capacity? integer
function Channel:init(capacity)
  capacity = capacity or 0
  if math.type(capacity) ~= "integer" or capacity < 0 then
    error(core.ArgumentError(("invalid channel capacity %s: expected an integer >= 0"):format(tostring(capacity))), 3)
  end
  self._capacity = capacity
  self._buffer, self._first, self._last = {}, 1, 0
  self._receivers = queue_new()
  self._senders = queue_new()
  self._closed = false
end

local function closed_error(self)
  return core.Error({
    message = "the channel is closed", code = "hecate.reactor.ChannelClosed", context = { channel = self },
  })
end

--- Returns the number of values waiting in the buffer.
---@return integer
function Channel:length() return self._last - self._first + 1 end

--- Returns whether the channel has been closed.
---@return boolean
function Channel:is_closed() return self._closed end

--- Sends `value`. Suspends while the buffer is full (or, for capacity 0, until a receiver
--- takes the value). Raises when the channel is, or becomes, closed.
---@async
---@param value any  not nil
function Channel:send(value)
  if value == nil then error(core.ArgumentError("a channel cannot carry nil"), 2) end
  if self._closed then error(closed_error(self), 2) end
  if queue_serve(self._receivers, function(r) return r.wake(value) end) then return end
  if self:length() < self._capacity then
    self._last = self._last + 1
    self._buffer[self._last] = value
    return
  end
  local result = wait_in(self._senders, { value = value })
  if result == CLOSED then error(closed_error(self), 2) end
end

--- Takes the oldest value; suspends while there is none. Returns nil once the channel is
--- closed and drained.
---@async
---@return any value
function Channel:receive()
  if self:length() > 0 then
    local value = self._buffer[self._first]
    self._buffer[self._first] = nil
    self._first = self._first + 1
    if self._first > self._last then self._first, self._last = 1, 0 end
    -- A suspended sender moves into the room just made.
    queue_serve(self._senders, function(s)
      if not s.wake(true) then return false end
      self._last = self._last + 1
      self._buffer[self._last] = s.value
      return true
    end)
    return value
  end
  local sender = queue_serve(self._senders, function(s) return s.wake(true) end)
  if sender then return sender.value end
  if self._closed then return nil end
  local value = wait_in(self._receivers, {})
  if value == CLOSED then return nil end
  return value
end

--- Closes the channel: pending and later sends raise, receivers drain the buffer and then
--- get nil. Closing twice is allowed.
function Channel:close()
  if self._closed then return end
  self._closed = true
  while queue_serve(self._receivers, function(r) return r.wake(CLOSED) end) do end
  while queue_serve(self._senders, function(s) return s.wake(CLOSED) end) do end
end

--- Returns a future that completes with the next received value, for `select`/`join`.
--- Cancelling the future (for instance, losing a `select`) abandons the receive; a value
--- already handed over at that moment is delivered to the future and dropped with it.
---@async
---@return hecate.reactor.Future
function Channel:receive_future()
  local task = context.current_task("Channel:receive_future")
  return task.reactor:_create_task(task.scope, function() return self:receive() end, { n = 0 })
end

--- Returns a future that completes once `value` has been sent.
---@async
---@param value any
---@return hecate.reactor.Future
function Channel:send_future(value)
  local task = context.current_task("Channel:send_future")
  return task.reactor:_create_task(task.scope, function() return self:send(value) end, { n = 0 })
end

M.Channel = core.finalise(Channel)

-- Semaphore and Mutex.

--- A permit: release it with `release` or by leaving the scope of a `<close>` variable.
---@class hecate.reactor.Permit
---@overload fun(owner: table): hecate.reactor.Permit
local Permit = core.class("Permit")

---@param owner table  the semaphore (or mutex) that issued the permit
function Permit:init(owner)
  self._owner = owner
  self._held = true
end

--- Returns the permit; harmless when already returned.
function Permit:release()
  if not self._held then return end
  self._held = false
  self._owner:_release()
end

--- Returns whether the permit is still held.
---@return boolean
function Permit:held() return self._held end

function Permit:__close() self:release() end

M.Permit = core.finalise(Permit)

---@class hecate.reactor.Semaphore
---@overload fun(permits: integer): hecate.reactor.Semaphore
local Semaphore = core.class("Semaphore")

--- Creates a semaphore with `permits` permits available.
---@param permits integer  >= 0
function Semaphore:init(permits)
  if math.type(permits) ~= "integer" or permits < 0 then
    error(core.ArgumentError(("invalid permit count %s: expected an integer >= 0"):format(tostring(permits))), 3)
  end
  self._available = permits
  self._waiters = queue_new()
end

--- Returns the number of permits available now.
---@return integer
function Semaphore:available() return self._available end

---@private
function Semaphore:_release()
  -- Hand the permit straight to the first live waiter, so nobody can overtake it.
  if not queue_serve(self._waiters, function(w) return w.wake() end) then
    self._available = self._available + 1
  end
end

---@param uncancellable? boolean
---@return hecate.reactor.Permit
---@private
function Semaphore:_acquire(uncancellable)
  context.current_task("Semaphore:acquire")
  if self._available > 0 and queue_peek(self._waiters) == nil then
    self._available = self._available - 1
  else
    wait_in(self._waiters, {}, uncancellable)
  end
  return Permit(self)
end

--- Takes a permit, suspending until one is available. Use it with `<close>`.
---@async
---@return hecate.reactor.Permit
function Semaphore:acquire() return self:_acquire(false) end

--- Takes a permit if one is available now, without suspending; otherwise returns nil.
---@return hecate.reactor.Permit?
function Semaphore:try_acquire()
  if self._available > 0 and queue_peek(self._waiters) == nil then
    self._available = self._available - 1
    return Permit(self)
  end
  return nil
end

M.Semaphore = core.finalise(Semaphore)

---@class hecate.reactor.Mutex
---@overload fun(): hecate.reactor.Mutex
local Mutex = core.class("Mutex", Semaphore)

--- Creates an unlocked mutex (not reentrant).
function Mutex:init() Semaphore.init(self, 1) end

--- Locks the mutex, suspending while another coroutine holds it. Use it with `<close>`.
---@async
---@return hecate.reactor.Permit
function Mutex:lock() return self:_acquire(false) end

--- Locks the mutex if it is free, without suspending; otherwise returns nil.
---@return hecate.reactor.Permit?
function Mutex:try_lock() return self:try_acquire() end

--- Returns whether the mutex is locked.
---@return boolean
function Mutex:is_locked() return self._available == 0 end

M.Mutex = core.finalise(Mutex)

-- Monitor and Condition.

---@class hecate.reactor.Monitor
---@overload fun(): hecate.reactor.Monitor
local Condition
local Monitor = core.class("Monitor")

--- Creates a monitor: a mutex whose holder may wait on its conditions.
function Monitor:init()
  self._mutex = Mutex()
  self._owner = nil
end

--- Enters the monitor, suspending while another coroutine is inside. Use it with `<close>`.
---@async
---@return hecate.reactor.Permit
function Monitor:enter()
  local task = context.current_task("Monitor:enter")
  if self._owner == task then error(core.Error("the coroutine is already inside this monitor"), 2) end
  local permit = self._mutex:lock()
  self._owner = task
  -- The monitor's own permit: leaving clears the owner before unlocking.
  local monitor = self
  return Permit({ _release = function() monitor._owner = nil; permit:release() end })
end

--- Returns whether the running coroutine is inside the monitor.
---@return boolean
function Monitor:is_inside()
  local reactor = context.reactor
  local task = reactor and reactor._tasks[coroutine.running()]
  return task ~= nil and self._owner == task
end

--- Returns a new condition attached to this monitor.
---@return hecate.reactor.Condition
function Monitor:condition() return Condition(self) end

M.Monitor = core.finalise(Monitor)

---@class hecate.reactor.Condition
---@overload fun(monitor: hecate.reactor.Monitor): hecate.reactor.Condition
Condition = core.class("Condition")

---@param monitor hecate.reactor.Monitor
function Condition:init(monitor)
  if not core.is_instance_of(monitor, Monitor) then
    error(core.ArgumentError("Condition expects a Monitor"), 3)
  end
  self._monitor = monitor
  self._waiters = queue_new()
end

--- Leaves the monitor, suspends until signalled, then re-enters the monitor before
--- returning (also when cancelled, so the caller's `<close>` handlers run inside it).
--- Mesa semantics: re-check the predicate in a loop.
---@async
function Condition:wait()
  local monitor = self._monitor
  if not monitor:is_inside() then
    error(core.Error("Condition:wait requires the running coroutine to be inside the monitor"), 2)
  end
  local task = monitor._owner
  monitor._owner = nil
  monitor._mutex:_release()
  local ok, err = pcall(wait_in, self._waiters, {})
  monitor._mutex:_acquire(true)
  monitor._owner = task
  if not ok then error(err, 0) end
end

--- Wakes the longest-waiting coroutine, if any.
function Condition:signal()
  queue_serve(self._waiters, function(w) return w.wake() end)
end

--- Wakes every waiting coroutine.
function Condition:broadcast()
  while queue_serve(self._waiters, function(w) return w.wake() end) do end
end

M.Condition = core.finalise(Condition)

return M
