-- Micro-benchmark: method dispatch on a finalised class versus raw metatables.
-- Usage: lua packages/core/benchmarks/dispatch.lua   (from the repository root)
global <const> package, os, string, print, setmetatable, require
package.path = "packages/core/src/?.lua;packages/core/src/?/init.lua;" .. package.path
local core = require("hecate.core")

local N = 20000000

local Base = core.class("Base")
function Base:value() return 1 end
core.finalise(Base)
local Derived = core.class("Derived", Base)
core.finalise(Derived)
local finalised = Derived()

local Raw = {}
Raw.__index = Raw
function Raw:value() return 1 end
local raw = setmetatable({}, Raw)

local function run(label, object)
  local start = os.clock()
  local sum = 0
  for _ = 1, N do sum = sum + object:value() end
  print(string.format("%-34s %.3f s for %d calls", label, os.clock() - start, N))
end

run("raw metatable", raw)
run("finalised subclass (flattened)", finalised)
