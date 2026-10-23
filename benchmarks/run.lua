-- Network scenario runner: starts the server of a scenario, drives it with the scenario's load generator for
-- several rounds, stops it, and prints the median and spread of every measure.
-- Usage: lua benchmarks/run.lua <scenario> [--rounds=N] [--server-pin=CPUS] [--load-pin=CPUS]
--          [--lua=PATH] [load options: --connections=N --rate=N --duration=S --warmup=S --payload=BYTES]
-- Run from the repository root, on Linux or macOS (a POSIX shell is required). Scenarios live in
-- benchmarks/scenarios/<name>/ as `server.lua` (prints `listening <port>`) and `load.lua`
-- (prints `label value unit` lines); benchmarks/README.md describes the method.
local stats = dofile("benchmarks/lib/stats.lua")
local runner = dofile("benchmarks/lib/runner.lua")

---@param message string
---@return never
local function fail(message)
  io.stderr:write("run.lua: ", message, "\n")
  os.exit(2)
end

local scenario = arg[1]
if not scenario or scenario:sub(1, 2) == "--" then fail("usage: lua benchmarks/run.lua <scenario> [options]") end
local options = { rounds = 5, lua = arg[-1] or "lua", load_args = {} }
for i = 2, #arg do
  local key, value = arg[i]:match("^%-%-([%w-]+)=(.*)$")
  if key == "rounds" then options.rounds = tonumber(value) or fail("--rounds needs a number")
  elseif key == "server-pin" then options.server_pin = value
  elseif key == "load-pin" then options.load_pin = value
  elseif key == "lua" then options.lua = value
  elseif key then options.load_args[#options.load_args + 1] = arg[i]
  else fail(("unknown argument '%s'"):format(arg[i])) end
end
if not runner.exists(scenario) then fail(("no scenario '%s' (see benchmarks/scenarios/)"):format(scenario)) end

local rounds = {}
for round = 1, options.rounds do
  io.stderr:write(("[round %d/%d] %s\n"):format(round, options.rounds, scenario))
  local measures, problem = runner.round(scenario, options)
  if not measures then fail(problem) end
  rounds[#rounds + 1] = measures
end

print(("# %s, %d rounds"):format(scenario, options.rounds))
print(("%-20s %12s %12s %12s %8s"):format("measure", "median", "min", "max", "max/min"))
for index, first in ipairs(rounds[1]) do
  local values = {}
  for r = 1, #rounds do values[r] = rounds[r][index].value end
  local lowest, highest = math.min(table.unpack(values)), math.max(table.unpack(values))
  print(("%-20s %12.1f %12.1f %12.1f %8.2f  %s"):format(first.label, stats.median(values), lowest, highest,
    lowest > 0 and highest / lowest or 0, first.unit))
end
