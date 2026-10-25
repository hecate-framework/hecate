-- accept-spread server: a primary and N worker processes echo what they receive, to measure how connections
-- spread over the workers under each listening strategy of ADR 0023 (`round_robin`, `reuseport`).
-- Usage: lua benchmarks/scenarios/accept-spread/server.lua [port] [strategy] [workers]   (from the repository root)
-- Prints `listening <port> <control port>` once every worker is ready (or `skipped <reason>` when the strategy
-- cannot run here), then runs until it is killed; workers exit when the primary does. A connection to the control
-- port is answered with one `<worker> <accepted connections>` line per worker.
global <const> _VERSION, package, io, os, arg, print, require, tonumber, tostring, ipairs, pcall, assert, string, table, math
-- HECATE_SRC: the checkout whose packages are measured (default: the current directory), so that the
-- A/B comparison runs one set of scenario files against a base and a head tree.
local src = os.getenv("HECATE_SRC") or "."
for _, name in ipairs({ "core", "reactor" }) do
  package.path = ("%s/packages/%s/src/?.lua;%s/packages/%s/src/?/init.lua;"):format(src, name, src, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
  if src ~= "." then package.cpath = src .. "/" .. tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath end
end

local reactor = require("hecate.reactor")

local function serve(stream)
  local peer <close> = stream
  peer:set_nodelay(true)
  while true do
    local data = peer:read(65536)
    if data == nil then return end -- the client closed its end
    peer:write(data)
  end
end

--- A worker: serves the connections it takes, counts them, and answers `stats` on the message pipe.
---@param parent hecate.reactor.Peer
---@param strategy string
---@param port integer
local function worker(parent, strategy, port)
  local accepted = 0
  local function take(stream)
    accepted = accepted + 1
    reactor.detach(function() pcall(serve, stream) end)
  end
  if strategy == "reuseport" then
    local listener <close> = reactor.tcp_listen("0.0.0.0", port, { reuseport = true, backlog = 4096 })
    reactor.detach(function() while true do take(listener:accept()) end end)
    parent:send("ready")
  else
    parent:send("ready")
  end
  while true do
    local message, stream = parent:receive()
    if message == nil then return end -- the primary is gone
    if stream then take(stream) elseif message == "stats" then parent:send(tostring(accepted)) end
  end
end

--- The primary: starts the workers, hands out connections for `round_robin`, serves the control port.
---@param port integer
---@param strategy string
---@param count integer
local function primary(port, strategy, count)
  if strategy ~= "round_robin" and strategy ~= "reuseport" then
    io.stderr:write(("unknown strategy '%s'\n"):format(strategy))
    os.exit(2)
  end
  if strategy == "reuseport" and not reactor.supports_reuseport() then
    print("skipped reuseport is not available (see reactor.supports_reuseport, OQ-43)")
    io.stdout:flush()
    return
  end
  local listener <close> = reactor.tcp_listen("0.0.0.0", port, { backlog = 4096, reuseport = strategy == "reuseport" })
  port = listener:local_address().port
  if strategy == "reuseport" then listener:close() end -- the workers bind the port: the primary must not accept
  local workers = {}
  for i = 1, count do
    workers[i] = reactor.spawn(arg[-1] or "lua", { arg[0], tostring(port), strategy, tostring(count), "--worker" }, { ipc = true })
    assert(workers[i].ipc:receive() == "ready", "a worker did not become ready")
  end
  local control <close> = reactor.tcp_listen("127.0.0.1", 0)
  print(("listening %d %d"):format(port, control:local_address().port))
  io.stdout:flush()
  reactor.detach(function()
    while true do
      local stream <close> = control:accept()
      local lines = {}
      for i, process in ipairs(workers) do
        process.ipc:send("stats")
        lines[i] = ("%d %s\n"):format(i, process.ipc:receive())
      end
      stream:write(table.concat(lines))
    end
  end)
  if strategy == "reuseport" then
    reactor.sleep(math.huge)
  else
    local next_worker = 0
    while true do
      local stream = listener:accept()
      next_worker = next_worker % count + 1
      pcall(workers[next_worker].ipc.send, workers[next_worker].ipc, "conn", stream)
    end
  end
end

local port, strategy, count = tonumber(arg[1]) or 0, arg[2] or "round_robin", tonumber(arg[3]) or 4
reactor.run(function()
  if arg[4] == "--worker" then
    worker(assert(reactor.ipc.parent(), "a worker needs its message pipe"), strategy, port)
  else
    primary(port, strategy, count)
  end
end)
