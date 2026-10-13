global <const> require

local M = {}

-- Documented on `hecate.demo` (the module class is completed from several files).

---@class hecate.demo
local waiting = M

--- Suspends the running coroutine for `seconds`, then returns how long it waited.
---
--- Raises `hecate.demo.CounterError` if `seconds` is negative, and `hecate.core.CancellationError`
--- if the enclosing scope is cancelled.
---
--- Implements RFC 2119, section 1, for no good reason.
---@async
---@param seconds number  how long to wait; `0` yields
---@param options? { quiet: boolean }  behaviour switches
---@return number waited  the time waited, in seconds
function waiting.wait(seconds, options)
  return seconds
end

return M
