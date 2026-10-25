-- One round of a network scenario: start its server, drive it with its load generator, stop it.
-- Shared by benchmarks/run.lua and benchmarks/compare.lua. Needs a POSIX shell.
local M = {}

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function pinned(cpus, command)
  if cpus then return ("taskset -c %s %s"):format(cpus, command) end
  return command
end

--- Whether the scenario exists.
---@param scenario string
---@return boolean
function M.exists(scenario)
  local f = io.open("benchmarks/scenarios/" .. scenario .. "/server.lua")
  if f then f:close() end
  return f ~= nil
end

--- Runs one round.
---@param scenario string
---@param o { lua: string, src?: string, server_pin?: string, load_pin?: string, load_args?: string[] }
---@return { label: string, value: number, unit: string }[]? measures
---@return string? problem
function M.round(scenario, o)
  local dir = "benchmarks/scenarios/" .. scenario
  local env = o.src and ("HECATE_SRC=%s "):format(quote(o.src)) or ""
  -- the shell prints its pid, then becomes the server, so that `kill` stops the right process
  local server = assert(io.popen(("echo $$; %sexec %s"):format(env,
    pinned(o.server_pin, ("%s %s/server.lua 0 2>&1"):format(quote(o.lua), dir))), "r"))
  local pid = server:read("l")
  local port = (server:read("l") or ""):match("^listening (%d+)$")
  if not port then
    os.execute("kill " .. pid .. " 2>/dev/null")
    server:close()
    return nil, "the server did not report its port"
  end
  local command = env .. pinned(o.load_pin, ("%s %s/load.lua --port=%s %s 2>&1"):format(
    quote(o.lua), dir, port, table.concat(o.load_args or {}, " ")))
  local load = assert(io.popen(command, "r"))
  local text = load:read("a")
  local ok = load:close()
  os.execute("kill " .. pid)
  server:close()
  if not ok then return nil, "the load generator failed:\n" .. text end
  local measures = {}
  for label, value, unit in text:gmatch("(%a[%w .]-)%s+(%-?[%d.]+)%s+(%S+)\n") do
    measures[#measures + 1] = { label = label, value = tonumber(value), unit = unit }
  end
  return measures
end

return M
