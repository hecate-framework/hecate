-- FIFO queue of waiters shared by the synchronisation primitives (Dijkstra 1965; Hoare 1974).
-- Intrusive doubly linked list: appending, removing a withdrawn waiter and popping are O(1).
-- A waiter is a table with a `wake(...)` function (the single-use wake-up of a suspension,
-- which returns false when the suspension has already ended) and optional payload fields.
-- Not public API.
global <const> require

local core = require("hecate.core")

---@class hecate.reactor.internal.Waiter
---@field wake fun(...): boolean
---@field value? any  payload of a pending send
---@field _queue? hecate.reactor.internal.Waitq
---@field _prev? hecate.reactor.internal.Waiter
---@field _next? hecate.reactor.internal.Waiter

---@class hecate.reactor.internal.Waitq
---@field size integer
---@field first? hecate.reactor.internal.Waiter
---@field last? hecate.reactor.internal.Waiter
---@overload fun(): hecate.reactor.internal.Waitq
local Waitq = core.class("Waitq")

--- Creates an empty queue.
function Waitq:init()
  self.size = 0
  self.first, self.last = nil, nil
end

--- Appends a waiter at the end of the queue.
---@param waiter hecate.reactor.internal.Waiter
---@return hecate.reactor.internal.Waiter waiter
function Waitq:push(waiter)
  waiter._queue, waiter._prev, waiter._next = self, self.last, nil
  if self.last then self.last._next = waiter else self.first = waiter end
  self.last = waiter
  self.size = self.size + 1
  return waiter
end

--- Withdraws a waiter (no effect when it is not queued).
---@param waiter hecate.reactor.internal.Waiter
function Waitq:remove(waiter)
  if waiter._queue ~= self then return end
  local prev, next = waiter._prev, waiter._next
  if prev then prev._next = next else self.first = next end
  if next then next._prev = prev else self.last = prev end
  waiter._queue, waiter._prev, waiter._next = nil, nil, nil
  self.size = self.size - 1
end

--- Wakes the first waiter whose suspension is still live, with the given values, and
--- removes it; waiters whose suspension already ended (cancelled) are skipped, so a hand-off
--- is never lost. Returns the woken waiter, or nil when there is none.
---@param ... any
---@return hecate.reactor.internal.Waiter?
function Waitq:wake_first(...)
  while true do
    local waiter = self.first
    if not waiter then return nil end
    self:remove(waiter)
    if waiter.wake(...) then return waiter end
  end
end

--- Reports whether no waiter is queued. A cancelled waiter stays queued until its task
--- resumes and withdraws it, so a false result may count a waiter that is about to leave.
---@return boolean
function Waitq:is_empty() return self.size == 0 end

return core.finalise(Waitq)
