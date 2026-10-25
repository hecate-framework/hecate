-- accept-spread load: opens short connections at a constant arrival rate (one request and one reply each), then asks
-- the server's control port how many connections every worker accepted.
-- Usage: lua benchmarks/scenarios/accept-spread/load.lua --port=N --control=N [--host=ADDR]
--          [--rate=CONNECTIONS_PER_SECOND] [--duration=SECONDS] [--payload=BYTES]
-- Prints measurement lines (`label value unit`): connection rate, errors, the spread (largest to smallest worker),
-- the connect-to-reply latency percentiles and the connections accepted by each worker.
global <const> _VERSION, package, io, arg, print, require, tonumber, ipairs, pcall, string, table, os, dofile, math
local src = os.getenv("HECATE_SRC") or "."
for _, name in ipairs({ "core", "reactor", "net" }) do
  package.path = ("%s/packages/%s/src/?.lua;%s/packages/%s/src/?/init.lua;"):format(src, name, src, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
  if src ~= "." then package.cpath = src .. "/" .. tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath end
end

local reactor = require("hecate.reactor")
local net = require("hecate.net")
local stats = dofile("benchmarks/lib/stats.lua")
local spread = dofile("benchmarks/scenarios/accept-spread/spread.lua")

local options = { host = "127.0.0.1", port = nil, control = nil, rate = 1000, duration = 10, payload = 64 }
for _, a in ipairs(arg) do
  local key, value = a:match("^%-%-(%a+)=(.*)$")
  if not key or options[key] == nil and key ~= "port" and key ~= "control" then
    io.stderr:write(("unknown argument '%s'\n"):format(a))
    os.exit(2)
  end
  options[key] = key == "host" and value or tonumber(value)
end
if not options.port or not options.control then
  io.stderr:write("--port and --control are required\n")
  os.exit(2)
end

local payload = ("x"):rep(options.payload)

local function run()
  local latencies, errors, completed = {}, 0, 0
  local interval = 1 / options.rate
  local start = reactor.now() + 0.2
  local total = math.floor(options.duration * options.rate)
  local tasks = {}
  for index = 1, total do
    local due = start + (index - 1) * interval
    local wait = due - reactor.now()
    if wait > 0 then reactor.sleep(wait) end
    tasks[#tasks + 1] = reactor.fork(function()
      local ok = pcall(function()
        local peer <close> = net.connect(options.host, options.port, { nodelay = true })
        peer:write(payload)
        peer:reader():read_exact(#payload)
      end)
      if ok then
        completed = completed + 1
        latencies[#latencies + 1] = reactor.now() - due -- from the instant the connection was due
      else
        errors = errors + 1
      end
    end)
  end
  reactor.join(table.unpack(tasks))
  local elapsed = reactor.now() - start
  local counts = {}
  local control <close> = net.connect("127.0.0.1", options.control)
  local reader, reply = control:reader(), {}
  while true do
    local chunk = reader:read_some()
    if chunk == nil then break end
    reply[#reply + 1] = chunk
  end
  for line in table.concat(reply):gmatch("[^\n]+") do
    counts[#counts + 1] = tonumber(line:match("^%d+ (%d+)$"))
  end
  return latencies, errors, completed, elapsed, counts
end

local latencies, errors, completed, elapsed, counts = reactor.run(run)
local microseconds = function(seconds) return seconds * 1e6 end
print(("throughput %.0f connections/s"):format(completed / elapsed))
print(("errors %d connections"):format(errors))
print(("spread %.2f ratio"):format(spread.ratio(counts)))
if #latencies > 0 then
  table.sort(latencies)
  for _, p in ipairs({ { "p50", 50 }, { "p99", 99 } }) do
    print(("latency %s %.1f us"):format(p[1], microseconds(stats.percentile(latencies, p[2]))))
  end
end
for index, count in ipairs(counts) do print(("worker %d accepted %d connections"):format(index, count)) end
