-- A/B comparison of a network scenario between a base tree and a head tree (benchmarks/README.md, OQ-14):
-- the same scenario files run against both, alternately (A/B/A/B) on the same host, and a regression is
-- reported only when the difference is significant (Mann-Whitney U, p < 0.01) and above 10 %.
-- Usage: lua benchmarks/compare.lua <scenario> --base=DIR [--head=DIR] [--rounds=N] [--lua=PATH]
--          [--server-pin=CPUS] [--load-pin=CPUS] [load options]
-- DIR is a checkout whose packages are measured (--head defaults to the current directory).
-- Exit status: 0 no regression, 1 regression, 2 usage or run error.
local stats = dofile("benchmarks/lib/stats.lua")
local runner = dofile("benchmarks/lib/runner.lua")

local ALPHA, THRESHOLD = 0.01, 0.10
-- measures that matter, and the direction in which a change is worse
local WATCHED = { ["throughput"] = "lower", ["latency p99"] = "higher" }

---@param message string
---@return never
local function fail(message)
  io.stderr:write("compare.lua: ", message, "\n")
  os.exit(2)
end

local scenario = arg[1]
if not scenario or scenario:sub(1, 2) == "--" then fail("usage: lua benchmarks/compare.lua <scenario> --base=DIR [options]") end
local options = { rounds = 5, lua = arg[-1] or "lua", load_args = {} }
local base, head = nil, "."
for i = 2, #arg do
  local key, value = arg[i]:match("^%-%-([%w-]+)=(.*)$")
  if key == "rounds" then options.rounds = tonumber(value) or fail("--rounds needs a number")
  elseif key == "base" then base = value
  elseif key == "head" then head = value
  elseif key == "server-pin" then options.server_pin = value
  elseif key == "load-pin" then options.load_pin = value
  elseif key == "lua" then options.lua = value
  elseif key then options.load_args[#options.load_args + 1] = arg[i]
  else fail(("unknown argument '%s'"):format(arg[i])) end
end
if not base then fail("--base=DIR is required") end
if options.rounds < 5 then fail("at least 5 rounds are needed for the test to mean anything") end
if not runner.exists(scenario) then fail(("no scenario '%s'"):format(scenario)) end

local samples = { base = {}, head = {} }
local order = {}
for round = 1, options.rounds do
  for _, side in ipairs(round % 2 == 1 and { "base", "head" } or { "head", "base" }) do
    io.stderr:write(("[round %d/%d] %s\n"):format(round, options.rounds, side))
    options.src = side == "base" and base or head
    local measures, problem = runner.round(scenario, options)
    if not measures then fail(side .. ": " .. problem) end
    for _, m in ipairs(measures) do
      if not samples[side][m.label] then
        samples[side][m.label] = {}
        if side == "base" then order[#order + 1] = { label = m.label, unit = m.unit } end
      end
      table.insert(samples[side][m.label], m.value)
    end
  end
end

local regressed = false
print(("# %s, base %s against head %s, %d rounds each"):format(scenario, base, head, options.rounds))
print(("%-16s %12s %12s %8s %8s  %s"):format("measure", "base", "head", "change", "p", "verdict"))
for _, m in ipairs(order) do
  local a, b = samples.base[m.label], samples.head[m.label]
  if b then
    local ma, mb = stats.median(a), stats.median(b)
    local change = ma ~= 0 and (mb - ma) / ma or 0
    local _, p = stats.mann_whitney(a, b)
    local verdict = "-"
    local direction = WATCHED[m.label]
    if direction then
      local worse = direction == "lower" and change < -THRESHOLD or direction == "higher" and change > THRESHOLD
      local better = direction == "lower" and change > THRESHOLD or direction == "higher" and change < -THRESHOLD
      if p < ALPHA and worse then verdict, regressed = "REGRESSION", true
      elseif p < ALPHA and better then verdict = "improvement"
      else verdict = "no significant change" end
    end
    print(("%-16s %12.1f %12.1f %+7.1f%% %8.4f  %s %s"):format(m.label, ma, mb, change * 100, p, verdict, m.unit))
  end
end
os.exit(regressed and 1 or 0)
