-- OQ-8 spike: how are connections spread over N worker processes, per listening strategy?
--
--   lua spike.lua <mode> [workers] [connections]                  (primary)
--   lua spike.lua worker <mode> <port> <id>                       (worker, started by the primary)
--
-- Modes:
--   reuseport      every worker binds the port itself with SO_REUSEPORT, through the `rp` C module
--                  (rp.c, built next to this file; Linux and macOS)
--   reuseport_luv  the same through `tcp:bind(host, port, { reuseport = true })`, which needs a
--                  luv patched as described in OQ-8 (luv 1.53 only knows it for UDP)
--   shared         the primary binds and listens, and passes the listening socket to every worker
--                  (libuv IPC handle passing); the workers accept on the shared socket
--   round_robin    the primary accepts and passes each connection to the next worker
--
-- Native rocks (luv) are found through the project-local tree `.hecate/rocks`, and the `rp`
-- module next to this file. This is spike code: it is not part of the framework.
local script_dir = (arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
local version = _VERSION:match("%d+%.%d+")
local rocks = script_dir .. "/../../../.hecate/rocks/lib/lua/" .. version
package.cpath = table.concat({
  rocks .. "/?.so", rocks .. "/?.dll", script_dir .. "/?.so", script_dir .. "/?.dll", package.cpath,
}, ";")
local uv = require("luv")

local function worker(mode, port, id)
  local function serve(server)
    server:listen(1024, function(err)
      assert(not err, err)
      local client = uv.new_tcp()
      server:accept(client)
      client:write(id .. "\n", function()
        client:shutdown(function() client:close() end)
      end)
    end)
  end
  if mode == "reuseport" then
    local server = uv.new_tcp()
    assert(server:open(require("rp").listen("127.0.0.1", port)))
    serve(server)
  elseif mode == "reuseport_luv" then
    local server = uv.new_tcp()
    assert(server:bind("127.0.0.1", port, { reuseport = true }))
    serve(server)
  else
    local ipc = uv.new_pipe(true)
    ipc:open(3)
    ipc:read_start(function(err, data)
      assert(not err, err)
      if not data then return end
      while ipc:pending_count() > 0 do
        local handle = uv.new_tcp()
        ipc:accept(handle)
        if mode == "shared" then
          serve(handle)
        else -- round_robin: the primary passed an accepted connection
          handle:write(id .. "\n", function() handle:shutdown(function() handle:close() end) end)
        end
      end
    end)
  end
  uv.run()
end

if arg[1] == "worker" then
  worker(arg[2], tonumber(arg[3]), arg[4])
  os.exit(0)
end

local mode = arg[1]
local nworkers = tonumber(arg[2]) or math.min(4, uv.available_parallelism())
local total = tonumber(arg[3]) or 4000
local port = 20000 + math.random(1000, 9000)
local reuse = mode == "reuseport" or mode == "reuseport_luv"
local workers, ipcs = {}, {}

local listener
if not reuse then
  listener = uv.new_tcp()
  assert(listener:bind("127.0.0.1", port))
end

for i = 1, nworkers do
  local ipc = (not reuse) and uv.new_pipe(true) or nil
  workers[i] = assert(uv.spawn("lua", {
    args = { arg[0], "worker", mode, tostring(port), tostring(i) },
    stdio = { nil, 1, 2, ipc },
  }, function() end))
  ipcs[i] = ipc
end

local function start_load()
  local tally, done, started, inflight = {}, 0, 0, 0
  local t0 = uv.hrtime()
  local function finish()
    local secs = (uv.hrtime() - t0) / 1e9
    local ids = {}
    for k in pairs(tally) do ids[#ids + 1] = k end
    table.sort(ids)
    local parts, lo, hi = {}, math.huge, 0
    for _, k in ipairs(ids) do
      parts[#parts + 1] = ("w%s=%d"):format(k, tally[k])
      lo, hi = math.min(lo, tally[k]), math.max(hi, tally[k])
    end
    print(("RESULT %s on %s: %d workers, %d connections in %.2fs (%.0f/s): %s; max/min = %.2f"):format(
      mode, uv.os_uname().sysname, nworkers, total, secs, total / secs, table.concat(parts, " "),
      hi / math.max(lo, 1)))
    for _, w in ipairs(workers) do w:kill("sigkill") end
    os.exit(0)
  end
  local function launch()
    while inflight < 100 and started < total do
      started = started + 1
      inflight = inflight + 1
      local c = uv.new_tcp()
      c:connect("127.0.0.1", port, function(err)
        local buf = {}
        local function complete(id)
          if not c:is_closing() then c:close() end
          tally[id] = (tally[id] or 0) + 1
          inflight, done = inflight - 1, done + 1
          if done == total then finish() end
          launch()
        end
        if err then return complete("error") end
        c:read_start(function(_, data)
          if data then buf[#buf + 1] = data return end
          complete(table.concat(buf):match("%d+") or "none")
        end)
      end)
    end
  end
  launch()
end

if mode == "shared" then
  for i = 1, nworkers do ipcs[i]:write2("x", listener, function() end) end
elseif mode == "round_robin" then
  local next_worker = 0
  listener:listen(1024, function(err)
    assert(not err, err)
    local c = uv.new_tcp()
    listener:accept(c)
    next_worker = next_worker % nworkers + 1
    ipcs[next_worker]:write2("c", c, function() c:close() end)
  end)
end
uv.new_timer():start(1000, 0, start_load) -- let the workers start (and bind)
-- Watchdog: a strategy that does not deliver every connection must not hang the run.
uv.new_timer():start(60000, 0, function()
  print(("RESULT %s on %s: TIMEOUT after 60s"):format(mode, uv.os_uname().sysname))
  for _, w in ipairs(workers) do w:kill("sigkill") end
  os.exit(1)
end)
uv.run()
