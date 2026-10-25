-- Micro-benchmark: cost of a disabled and of an enabled logger call (synchronous sink, no I/O).
-- Usage: lua packages/log/benchmarks/logger.lua   (from the repository root)
global <const> package, os, string, print, require, math, ipairs
for _, name in ipairs({ "log", "core", "json", "reactor" }) do
  package.path = "packages/" .. name .. "/src/?.lua;packages/" .. name .. "/src/?/init.lua;" .. package.path
end
local log = require("hecate.log")
local reactor = require("hecate.reactor")

local N = 2000000
local ROUNDS = 5

local sink = log.MemorySink({ capacity = 16 })
local logger = log.Logger({ level = "informational", sinks = { sink }, name = "bench", context = { service = "api" } })

local function run(label, call, count)
  count = count or N
  local best = math.huge
  for _ = 1, ROUNDS do
    local start = os.clock()
    for _ = 1, count do call() end
    local elapsed = os.clock() - start
    if elapsed < best then best = elapsed end
  end
  print(string.format("%-40s %7.0f ns/call (best of %d rounds)", label, best / count * 1e9, ROUNDS))
end

run("disabled call (debug < threshold)", function() logger:debug("hidden", { id = 1 }) end)
run("enabled call, no fields", function() logger:informational("shown") end)
run("enabled call, 3 fields", function() logger:informational("shown", { id = 1, route = "/x", ms = 4 }) end)
local child = logger:with_context({ request = "r-1" })
run("enabled call, child context + 3 fields", function() child:informational("shown", { id = 1, route = "/x", ms = 4 }) end)

-- Through an AsyncSink: queueing only, the drain task is outside the timed section. The queue holds
-- every record until the end, so fewer calls than above keep the memory small.
local QUEUED = 100000
reactor.Reactor():run(function()
  local async = log.AsyncSink({ sink = log.MemorySink({ capacity = 16 }), capacity = QUEUED * ROUNDS })
  local queued = log.Logger({ sinks = { async } })
  run("enabled call, AsyncSink (queueing)", function() queued:informational("shown", { id = 1 }) end, QUEUED)
  async:close()
end)
