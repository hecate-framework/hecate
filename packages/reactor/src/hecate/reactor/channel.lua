-- Channel: communication between coroutines (Hoare, "Communicating Sequential Processes",
-- 1978, section 2: input and output commands; capacity 0 is the rendezvous of CSP, where
-- sender and receiver proceed together). A positive capacity adds a FIFO buffer.
--   * Senders and receivers are served in FIFO order, by direct hand-off.
--   * Cancellation withdraws the waiter; a value is handed over only to a waiter whose
--     suspension is still live (single-use wake-up), so no value is lost or duplicated.
--   * `close` wakes every waiter with `ClosedChannelError`; buffered values stay receivable.
--   * `Channel:send_op(v)` and `Channel:receive_op()` build operations that `select` can
--     wait on together with futures (CSP alternative command, section 2.6).
global <const> math, error, require, tostring

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Waitq = require("hecate.reactor.internal.waitq")
local ChannelOperation = require("hecate.reactor.channel_operation")

local OK, CLOSED = true, false -- status handed to a suspended sender or receiver

---@param channel table
local function raise_closed(channel)
  error(core.ClosedChannelError({ message = "the channel is closed", context = { channel = channel } }), 0)
end

--- A channel between coroutines: a rendezvous when its capacity is 0, a FIFO buffer otherwise (Hoare 1978, section 2).
---@class hecate.reactor.Channel
---@overload fun(capacity?: integer): hecate.reactor.Channel
local Channel = core.class("Channel")

--- Creates a channel holding at most `capacity` values (0: rendezvous).
---@param capacity? integer  not negative; defaults to 0
function Channel:init(capacity)
  if capacity == nil then capacity = 0 end
  if math.type(capacity) ~= "integer" or capacity < 0 then
    error(core.ArgumentError(("Channel expects a non-negative integer capacity, got %s")
      :format(tostring(capacity))), 2)
  end
  self._capacity = capacity
  self._buffer = {}
  self._head, self._count = 1, 0
  self._closed = false
  self._senders = Waitq()
  self._receivers = Waitq()
end

---@param value any
local function buffer_push(self, value)
  self._buffer[self._head + self._count] = value
  self._count = self._count + 1
end

local function buffer_pop(self)
  local index = self._head
  local value = self._buffer[index]
  self._buffer[index] = nil
  self._count = self._count - 1
  self._head = self._count == 0 and 1 or index + 1
  return value
end

--- Hands `value` over without suspending. Returns false when the sender would have to wait.
---@return boolean sent
---@private
function Channel:_try_send(value)
  if self._closed then raise_closed(self) end
  if self._receivers:wake_first(OK, value) then return true end
  if self._count < self._capacity then
    buffer_push(self, value)
    return true
  end
  return false
end

--- Takes a value without suspending. Returns false when the receiver would have to wait.
---@return boolean received
---@return any value
---@private
function Channel:_try_receive()
  if self._count > 0 then
    local value = buffer_pop(self)
    local sender = self._senders:wake_first(OK) -- a room has opened in the buffer
    if sender then buffer_push(self, sender.value) end
    return true, value
  end
  local sender = self._senders:wake_first(OK) -- rendezvous
  if sender then return true, sender.value end
  if self._closed then raise_closed(self) end
  return false, nil
end

--- Sends `value` (any Lua value, `nil` included), suspending until a receiver takes it or,
--- on a buffered channel, until there is room. Raises `ClosedChannelError` if the channel is
--- closed before or while waiting.
---@async
---@param value any
function Channel:send(value)
  context.current_task("Channel:send")
  if self:_try_send(value) then return end
  local senders = self._senders
  local waiter
  local status = context.suspend(function(wake)
    waiter = senders:push({ wake = wake, value = value })
    return function() senders:remove(waiter) end
  end)
  if status == CLOSED then raise_closed(self) end
end

--- Receives the next value, suspending while there is none. A closed channel first yields
--- the values still buffered, then raises `ClosedChannelError`.
---@async
---@return any value
function Channel:receive()
  context.current_task("Channel:receive")
  local received, value = self:_try_receive()
  if received then return value end
  local receivers = self._receivers
  local waiter
  local status
  status, value = context.suspend(function(wake)
    waiter = receivers:push({ wake = wake })
    return function() receivers:remove(waiter) end
  end)
  if status == CLOSED then raise_closed(self) end
  return value
end

--- Closes the channel: pending and future sends raise `ClosedChannelError`, receivers drain
--- the buffer and then raise it. Closing a closed channel does nothing. Never suspends.
---@return boolean closed  true if this call closed the channel
function Channel:close()
  if self._closed then return false end
  self._closed = true
  while self._receivers:wake_first(CLOSED) do end
  while self._senders:wake_first(CLOSED) do end
  return true
end

--- Returns whether the channel is closed.
---@return boolean
function Channel:is_closed() return self._closed end

--- Returns the maximum number of buffered values.
---@return integer
function Channel:capacity() return self._capacity end

--- Returns the number of buffered values.
---@return integer
function Channel:length() return self._count end

--- Returns an operation sending `value`, for `select`.
---@param value any
---@return hecate.reactor.ChannelOperation
function Channel:send_op(value) return ChannelOperation(self, "send", value) end

--- Returns an operation receiving a value, for `select`.
---@return hecate.reactor.ChannelOperation
function Channel:receive_op() return ChannelOperation(self, "receive") end

return core.finalise(Channel)
