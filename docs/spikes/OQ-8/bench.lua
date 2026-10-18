-- usage: lua bench.lua <reuseport|round_robin> <churn|keepalive> [workers] [clients] [seconds]
-- The load generator runs in its own process, so the primary and the workers do not share a core
-- with it (the machine has 4 cores: 2 workers + primary + generator).
local script_dir = (arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
local rocks = script_dir .. "/../../../.hecate/rocks/lib/lua/" .. _VERSION:match("%d+%.%d+")
package.cpath = rocks .. "/?.so;" .. rocks .. "/?.dll;" .. script_dir .. "/?.so;" .. script_dir .. "/?.dll;" .. package.cpath
local uv = require("luv")

if arg[1] == "worker" then
  local mode, kind, port, id = arg[2], arg[3], tonumber(arg[4]), arg[5]
  local function serve_connection(client)
    client:read_start(function(err, data)
      if err or not data then client:close() return end
      client:write(id .. "\n")
      if kind == "churn" then client:shutdown(function() client:close() end) end
    end)
  end
  local function listen(server)
    server:listen(1024, function()
      local client = uv.new_tcp()
      server:accept(client)
      serve_connection(client)
    end)
  end
  if mode == "reuseport" then
    local server = uv.new_tcp()
    assert(server:open(require("rp").listen("127.0.0.1", port)))
    listen(server)
  else
    local ipc = uv.new_pipe(true)
    ipc:open(3)
    ipc:read_start(function(err, data)
      if err or not data then return end
      while ipc:pending_count() > 0 do
        local client = uv.new_tcp()
        ipc:accept(client)
        serve_connection(client)
      end
    end)
  end
  uv.run()
  os.exit(0)
end

if arg[1] == "loadgen" then
  local kind, port, clients, seconds = arg[2], tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
  local count, tally, stop = 0, {}, false
  local function note(data)
    local id = data:match("%d+") or "?"
    tally[id] = (tally[id] or 0) + 1
    count = count + 1
  end
  local function churn()
    if stop then return end
    local c = uv.new_tcp()
    c:connect("127.0.0.1", port, function(err)
      if err then c:close() return churn() end
      c:write("x\n")
      c:read_start(function(_, data)
        if data then note(data) end
        if not c:is_closing() then c:close() end
        churn()
      end)
    end)
  end
  local function keepalive()
    local c = uv.new_tcp()
    c:connect("127.0.0.1", port, function(err)
      if err then c:close() return end
      c:write("x\n")
      c:read_start(function(_, data)
        if not data then return end
        note(data)
        if not stop then c:write("x\n") end
      end)
    end)
  end
  for _ = 1, clients do if kind == "churn" then churn() else keepalive() end end
  uv.new_timer():start(seconds * 1000, 0, function()
    stop = true
    local ids, parts, lo, hi = {}, {}, math.huge, 0
    for k in pairs(tally) do ids[#ids + 1] = k end
    table.sort(ids)
    for _, k in ipairs(ids) do parts[#parts + 1] = k .. "=" .. tally[k]; lo = math.min(lo, tally[k]); hi = math.max(hi, tally[k]) end
    print(("RESULT %s %s: %.0f /s over %ds, %d clients; per worker %s; max/min %.2f"):format(
      arg[6], kind, count / seconds, seconds, clients, table.concat(parts, " "), hi / math.max(lo, 1)))
    os.exit(0)
  end)
  uv.run()
  os.exit(0)
end

local mode, kind = arg[1], arg[2]
local nworkers, clients, seconds = tonumber(arg[3]) or 2, tonumber(arg[4]) or 64, tonumber(arg[5]) or 5
local port = 20000 + math.random(1000, 9000)
local workers, ipcs, listener = {}, {}, nil
if mode == "round_robin" then
  listener = uv.new_tcp()
  assert(listener:bind("127.0.0.1", port))
end
for i = 1, nworkers do
  local ipc = mode == "round_robin" and uv.new_pipe(true) or nil
  workers[i] = assert(uv.spawn("lua", { args = { arg[0], "worker", mode, kind, tostring(port), tostring(i) }, stdio = { nil, 1, 2, ipc } }, function() end))
  ipcs[i] = ipc
end
if mode == "round_robin" then
  local nxt = 0
  listener:listen(4096, function()
    local c = uv.new_tcp()
    listener:accept(c)
    nxt = nxt % nworkers + 1
    ipcs[nxt]:write2("c", c, function() c:close() end)
  end)
end
uv.new_timer():start(1000, 0, function()
  uv.spawn("lua", { args = { arg[0], "loadgen", kind, tostring(port), tostring(clients), tostring(seconds), mode }, stdio = { nil, 1, 2 } }, function()
    local function cpu_of(pid)
      local fh = io.open("/proc/" .. pid .. "/stat", "rb")
      if not fh then return 0 end
      local stat = fh:read("a"); fh:close()
      local rest = stat:match("%) (.*)$")
      local fields = {}
      for v in rest:gmatch("%S+") do fields[#fields + 1] = v end
      return (tonumber(fields[12]) + tonumber(fields[13])) / 100 -- utime + stime, in seconds
    end
    local ru = uv.getrusage()
    local primary = ru.utime.sec + ru.utime.usec / 1e6 + ru.stime.sec + ru.stime.usec / 1e6
    local parts = {}
    for i, w in ipairs(workers) do parts[#parts + 1] = ("w%d %.1fs"):format(i, cpu_of(w:get_pid())) end
    print(("CPU over the run (about %ds, includes start-up): primary %.1fs, %s"):format(seconds, primary, table.concat(parts, ", ")))
    for _, w in ipairs(workers) do w:kill("sigkill") end
    os.exit(0)
  end)
end)
uv.run()
