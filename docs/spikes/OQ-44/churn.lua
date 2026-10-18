-- usage: lua churn.lua <mode> [requests] [inflight]
-- Coroutine-per-request churn with a large long-lived heap; reports throughput, per-step latency
-- tail and peak memory. Modes: inc_default, inc_150, inc_tuned, gen_default, gen_minor50, gen_major300
local script_dir = (arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
local rocks = script_dir .. "/../../../.hecate/rocks/lib/lua/" .. _VERSION:match("%d+%.%d+")
package.cpath = rocks .. "/?.so;" .. rocks .. "/?.dll;" .. package.cpath
local uv = require("luv")
local hrtime = uv.hrtime

local mode = arg[1] or "inc_default"
local requests = tonumber(arg[2]) or 200000
local inflight = tonumber(arg[3]) or 500

local modes = {
  inc_default = function() collectgarbage("incremental") end,
  inc_150 = function() collectgarbage("incremental", 150, 100, 13) end,
  inc_tuned = function() collectgarbage("incremental", 150, 400, 13) end,
  gen_default = function() collectgarbage("generational") end,
  gen_minor50 = function() collectgarbage("generational", 50, 100) end,
  inc_smallstep = function() collectgarbage("incremental", 200, 100, 10) end,
  inc_bigstep = function() collectgarbage("incremental", 200, 100, 20) end,
  gen_major300 = function() collectgarbage("generational", 20, 300) end,
}
modes[mode]()

-- Long-lived structures: route tables, compiled schemas, singletons (about 60 MB).
local old = {}
local OLD = tonumber(arg[4]) or 400000
for i = 1, OLD do
  old[i] = { id = i, name = "route" .. i, parts = { "a", "b", i }, handler = function() return i end }
end
collectgarbage()
collectgarbage()

local function handler(id)
  -- request table and headers
  local req = { id = id, headers = {}, query = {} }
  for k = 1, 12 do req.headers["x-header-" .. k] = "value-" .. id .. "-" .. k end
  coroutine.yield() -- waiting for the body
  -- decoded JSON tree
  local tree = {}
  for k = 1, 20 do tree[k] = { name = "n" .. k, tags = { "a", "b", "c" }, nested = { v = k, w = tostring(k * id) } } end
  coroutine.yield() -- waiting for the database
  -- coercion results
  local out = {}
  for k = 1, 20 do out[k] = { field = "f" .. k, value = tree[k].nested.w .. "!" } end
  coroutine.yield() -- waiting for the socket to drain
  return #out + #req.headers
end

local lat, n = {}, 0
local slow, maxdt, maxat = 0, 0, 0
local peak = 0
local ring = {}
local started, finished = 0, 0
local t_start = hrtime()
local function step(co, id)
  local t0 = hrtime()
  local ok = coroutine.resume(co, id)
  local dt = hrtime() - t0
  n = n + 1
  lat[n] = dt
  if dt > 5e6 then slow = slow + 1; if dt > maxdt then maxdt, maxat = dt, n end end
  return coroutine.status(co) == "dead"
end
local slot = 0
while finished < requests do
  slot = slot % inflight + 1
  local entry = ring[slot]
  if entry == nil then
    if started < requests then
      started = started + 1
      local co = coroutine.create(handler)
      ring[slot] = { co = co, id = started }
      if step(co, started) then ring[slot] = nil; finished = finished + 1 end
    end
  else
    if step(entry.co, entry.id) then ring[slot] = nil; finished = finished + 1 end
  end
  if n % 2000 == 0 then
    local c = collectgarbage("count")
    if c > peak then peak = c end
  end
end
local secs = (hrtime() - t_start) / 1e9
table.sort(lat)
local function pct(p) return lat[math.max(1, math.floor(#lat * p))] / 1000 end
print(("steps over 5 ms: %d, worst step #%d of %d (%.0f ms)"):format(slow, maxat, n, maxdt / 1e6))
print(("%-13s %6.0f req/s  step p50 %5.1f us  p99 %6.1f us  p99.9 %7.1f us  max %8.0f us  peak %5.0f MB"):format(
  mode, requests / secs, pct(0.5), pct(0.99), pct(0.999), lat[#lat] / 1000, peak / 1024))
