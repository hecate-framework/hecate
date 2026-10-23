-- tcp-echo load: opens connections to an echo server and sends one payload per connection at a constant
-- arrival rate; latency is measured from the instant a request was due, not from the instant it was sent,
-- so a slow server cannot hide its queueing (coordinated omission).
-- Usage: lua benchmarks/scenarios/tcp-echo/load.lua [--port=N] [--host=ADDR] [--connections=N]
--          [--rate=REQUESTS_PER_SECOND] [--duration=SECONDS] [--warmup=SECONDS] [--payload=BYTES]
-- Prints measurement lines (`label value unit`): throughput, errors, p50/p90/p99/p99.9 and max latency.
global <const> _VERSION, package, io, arg, print, require, tonumber, ipairs, pcall, string, table, os, dofile
for _, name in ipairs({ "core", "reactor", "net" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end

local reactor = require("hecate.reactor")
local net = require("hecate.net")
local stats = dofile("benchmarks/lib/stats.lua")

local options = { host = "127.0.0.1", port = nil, connections = 100, rate = 1000, duration = 10, warmup = 2, payload = 64 }
for _, a in ipairs(arg) do
  local key, value = a:match("^%-%-(%a+)=(.*)$")
  if not key or options[key] == nil and key ~= "port" then
    io.stderr:write(("unknown argument '%s'\n"):format(a))
    os.exit(2)
  end
  options[key] = key == "host" and value or tonumber(value)
end
if not options.port then
  io.stderr:write("--port is required\n")
  os.exit(2)
end

local payload = ("x"):rep(options.payload)
local interval = options.connections / options.rate -- seconds between two requests of one connection

local function run()
  local start, warm_until, stop -- set once every connection is open, so that connecting is not measured
  local latencies, errors, completed, pending = {}, 0, 0, options.connections

  local function client(index)
    local ok, connection = pcall(net.connect, options.host, options.port, { nodelay = true })
    pending = pending - 1
    if not ok then errors = errors + 1 return end
    local peer <close> = connection
    local reader = peer:reader()
    while not start do reactor.sleep(0.01) end
    -- connections are staggered over one interval so that arrivals are spread, not bursty
    local due = start + interval * (index - 1) / options.connections
    while due < stop do
      local wait = due - reactor.now()
      if wait > 0 then reactor.sleep(wait) end
      local sent = pcall(function()
        peer:write(payload)
        reader:read_exact(#payload)
      end)
      if not sent then
        errors = errors + 1
        return
      end
      if due >= warm_until then
        latencies[#latencies + 1] = reactor.now() - due
        completed = completed + 1
      end
      due = due + interval
    end
  end

  local scope = {}
  for i = 1, options.connections do scope[i] = reactor.fork(client, i) end
  while pending > 0 do reactor.sleep(0.01) end
  start = reactor.now() + 0.5
  warm_until = start + options.warmup
  stop = warm_until + options.duration
  reactor.join(table.unpack(scope))
  return latencies, errors, completed
end

local latencies, errors, completed = reactor.run(run)
local microseconds = function(seconds) return seconds * 1e6 end
print(("throughput %.0f requests/s"):format(completed / options.duration))
print(("errors %d connections"):format(errors))
if #latencies > 0 then
  table.sort(latencies)
  for _, p in ipairs({ { "p50", 50 }, { "p90", 90 }, { "p99", 99 }, { "p99.9", 99.9 } }) do
    print(("latency %s %.1f us"):format(p[1], microseconds(stats.percentile(latencies, p[2]))))
  end
  print(("latency max %.1f us"):format(microseconds(latencies[#latencies])))
end
