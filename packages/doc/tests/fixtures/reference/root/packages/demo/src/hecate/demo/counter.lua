global <const> require, type

local core = require("hecate.core")

local M = {}

--- Raised by counters and by `demo.add` on misuse.
---@class hecate.demo.CounterError : hecate.core.Error
M.CounterError = core.error_class("CounterError", "hecate.demo.CounterError")

--- Options of a counter.
---@class hecate.demo.CounterOptions
---@field step? integer  increment of one tick, default 1
---@field start? integer  initial value, default 0

--- A counter that counts up by a fixed step.
---@class hecate.demo.Counter
---@field value integer  the current value
---@field _secret integer  private bookkeeping
---@overload fun(options?: hecate.demo.CounterOptions): hecate.demo.Counter
local Counter = core.class("Counter")
M.Counter = Counter

--- Creates a counter.
---
--- Raises `hecate.demo.CounterError` if `options.step` is not an integer.
---@param options? hecate.demo.CounterOptions  step and start value
function Counter:init(options)
  self.value = options and options.start or 0
  self._secret = 0
end

--- Advances the counter by its step and returns the new value.
---@return integer value  the value after the tick
function Counter:tick()
  self.value = self.value + 1
  return self.value
end

--- Returns the value, or `nil` when the counter was reset.
---@return integer? value  the value, or `nil` after a reset
function Counter:peek()
  return self.value
end

--- Waits until the counter reaches `target`.
---@async
---@param target integer  the value to reach
---@return integer value  the value when the wait ends
function Counter:wait_for(target)
  return target
end

function Counter:_hidden() end

core.finalise(Counter)

return M
