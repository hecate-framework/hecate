-- One round of a network scenario: start its server, drive it with its load generator, stop it.
-- Shared by benchmarks/run.lua and benchmarks/compare.lua. Runs on `reactor.spawn`, so it works on Linux, macOS and
-- Windows and must be called from inside `reactor.run`. CPU pinning needs `taskset` (Linux); elsewhere it is refused.
local version = _VERSION:match("%d+%.%d+")
for _, name in ipairs({ "core", "reactor" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end
local reactor = require("hecate.reactor")

local M = {}

local function pinned(cpus, lua, script, args)
  local argv = { script }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  if not cpus then return lua, argv end
  return "taskset", { "-c", cpus, lua, table.unpack(argv) }
end

--- Whether the scenario exists.
---@param scenario string
---@return boolean
function M.exists(scenario)
  local f = io.open("benchmarks/scenarios/" .. scenario .. "/server.lua")
  if f then f:close() end
  return f ~= nil
end

--- Starts a scenario process with a message pipe; its report is the first message (the server) or the last (the load).
local function start(o, cpus, script, args)
  local program, argv = pinned(cpus, o.lua, script, args)
  return reactor.spawn(program, argv, { ipc = true, env = o.src and { HECATE_SRC = o.src } or nil })
end

--- Runs one round. Suspends: call it inside `reactor.run`.
---@param scenario string
---@param o { lua: string, src?: string, server_pin?: string, load_pin?: string, load_args?: string[] }
---@return { label: string, value: number, unit: string }[]? measures
---@return string? problem
function M.round(scenario, o)
  local dir = "benchmarks/scenarios/" .. scenario
  local server = start(o, o.server_pin, dir .. "/server.lua", { "0" })
  local function stop()
    server:kill()
    server:wait()
    server.ipc:close()
  end
  local port = (server.ipc:receive() or ""):match("^listening (%d+)$")
  if not port then
    stop()
    return nil, "the server did not report its port"
  end
  local args = { "--port=" .. port }
  for _, a in ipairs(o.load_args or {}) do args[#args + 1] = a end
  local load = start(o, o.load_pin, dir .. "/load.lua", args)
  local text = load.ipc:receive()
  local status = load:wait()
  load.ipc:close()
  stop()
  if not text or status.code ~= 0 then return nil, "the load generator failed" end
  local measures = {}
  for label, value, unit in (text .. "\n"):gmatch("(%a[%w .]-)%s+(%-?[%d.]+)%s+(%S+)\n") do
    measures[#measures + 1] = { label = label, value = tonumber(value), unit = unit }
  end
  return measures
end

return M
