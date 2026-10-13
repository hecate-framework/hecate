-- Fixture package for the reference generator tests: its LuaLS export is checked in as
-- ../../../export.json (see tests/unit/reference_test.lua).
global <const> require

local counter = require("hecate.demo.counter")
local waiting = require("hecate.demo.waiting")

--- A small demonstration package: counters and a suspending wait.
---@class hecate.demo
---@field Counter hecate.demo.Counter  counts up
---@field CounterError hecate.demo.CounterError  raised by counters
---@field limit integer  largest value a counter can reach
local demo = {
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Counter = counter.Counter,
  CounterError = counter.CounterError,
  limit = 100,
}

demo.wait = waiting.wait

--- Adds two integers.
---
--- The sum wraps around like any Lua integer.
---
--- Raises `hecate.demo.CounterError` when `a` or `b` is not an integer.
---
--- Since 0.2.
---@param a integer  the first addend
---@param b integer  the second addend
---@return integer sum  the sum of the addends
---@see hecate.demo.wait
function demo.add(a, b)
  return a + b
end

--- Returns the name of the package.
---@return string name
function demo.name()
  return "demo"
end

---@param value any
function demo.undocumented(value) return value end

return demo
