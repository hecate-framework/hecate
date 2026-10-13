-- ChannelOperation: a pending send or receive on a channel, built by `Channel:send_op` and
-- `Channel:receive_op` for `select` (Hoare, "CSP", 1978, section 2.6: alternative command).
global <const> require

local core = require("hecate.core")

--- Operations are descriptors: they do nothing until `select` commits one, and may be reused.
---@class hecate.reactor.ChannelOperation
---@field channel hecate.reactor.Channel
---@field kind "send"|"receive"
---@field value any  the value to send
---@overload fun(channel: hecate.reactor.Channel, kind: "send"|"receive", value?: any): hecate.reactor.ChannelOperation
local ChannelOperation = core.class("ChannelOperation")

---@param channel hecate.reactor.Channel
---@param kind "send"|"receive"
---@param value? any
function ChannelOperation:init(channel, kind, value)
  self.channel, self.kind, self.value = channel, kind, value
end

--- Tries the operation without suspending (used by `select`). Returns whether it
--- completed and, for a receive, the value. Raises `ClosedChannelError`.
---@return boolean completed
---@return any value
---@private
function ChannelOperation:_try()
  if self.kind == "send" then
    ---@diagnostic disable-next-line: invisible  -- friend class
    return self.channel:_try_send(self.value), nil
  end
  ---@diagnostic disable-next-line: invisible
  return self.channel:_try_receive()
end

--- Queues a waiter for the operation; `wake(status, value)` returns false when the
--- suspension it belongs to has already ended. Returns the function withdrawing the waiter.
---@param wake fun(status: boolean, value?: any): boolean
---@return fun() withdraw
---@private
function ChannelOperation:_enqueue(wake)
  local channel = self.channel
  local queue = self.kind == "send" and channel._senders or channel._receivers
  local waiter = queue:push({ wake = wake, value = self.value })
  return function() queue:remove(waiter) end
end

return core.finalise(ChannelOperation)
