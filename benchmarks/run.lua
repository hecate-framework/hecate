-- Network scenario runner: starts the server of a scenario, drives it with the scenario's load generator for
-- several rounds, stops it, and prints the median and spread of every measure.
-- Usage: lua benchmarks/run.lua <scenario> [--rounds=N] [--server-pin=CPUS] [--load-pin=CPUS]
--          [--lua=PATH] [load options: --connections=N --rate=N --duration=S --warmup=S --payload=BYTES]
-- Run from the repository root, on Linux or macOS (a POSIX shell is required). Scenarios live in
-- benchmarks/scenarios/<name>/ as `server.lua` (prints `listening <port>`) and `load.lua`
-- (prints `label value unit` lines); benchmarks/README.md describes the method.
local stats = dofile("benchmarks/lib/stats.lua")

local function fail(message)
  io.stderr:write("run.lua: ", message, "\n")
  os.exit(2)
end

local scenario = arg[1]
if not scenario or scenario:sub(1, 2) == "--" then fail("usage: lua benchmarks/run.lua <scenario> [options]") end
local options = { rounds = 5, lua = arg[-1] or "lua" }
local load_args = {}
for i = 2, #arg do
  local key, value = arg[i]:match("^%-%-([%w-]+)=(.*)$")
  if key == "rounds" then options.rounds = tonumber(value) or fail("--rounds needs a number")
  elseif key == "server-pin" then options.server_pin = value
  elseif key == "load-pin" then options.load_pin = value
  elseif key == "lua" then options.lua = value
  elseif key then load_args[#load_args + 1] = arg[i]
  else fail(("unknown argument '%s'"):format(arg[i])) end
end

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local dir = "benchmarks/scenarios/" .. scenario
if not io.open(dir .. "/server.lua") then fail(("no scenario '%s' (expected %s/server.lua)"):format(scenario, dir)) end

local function pinned(cpus, command)
  if cpus then return ("taskset -c %s %s"):format(cpus, command) end
  return command
end

local rounds = {}
for round = 1, options.rounds do
  -- the shell prints its pid, then becomes the server, so that `kill` stops the right process
  local server = assert(io.popen(("echo $$; exec %s"):format(
    pinned(options.server_pin, ("%s %s/server.lua 0 2>&1"):format(quote(options.lua), dir))), "r"))
  local pid = server:read("l")
  local port = (server:read("l") or ""):match("^listening (%d+)$")
  if not port then fail("the server did not report its port") end
  local command = pinned(options.load_pin, ("%s %s/load.lua --port=%s %s 2>&1"):format(
    quote(options.lua), dir, port, table.concat(load_args, " ")))
  io.stderr:write(("[round %d/%d] %s\n"):format(round, options.rounds, scenario))
  local load = assert(io.popen(command, "r"))
  local text = load:read("a")
  local ok = load:close()
  os.execute("kill " .. pid)
  server:close()
  if not ok then fail("the load generator failed:\n" .. text) end
  local measures = {}
  for label, value, unit in text:gmatch("(%a[%w .]-)%s+(%-?[%d.]+)%s+(%S+)\n") do
    measures[#measures + 1] = { label = label, value = tonumber(value), unit = unit }
  end
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
