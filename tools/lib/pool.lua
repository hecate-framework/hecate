-- A pool of worker processes for the test task. Standard library only (no luv in the tools): each job is a
-- shell command started with io.popen, at most `workers` at a time; the handles are read in start order, so the
-- results come back in job order whatever the order in which the processes finish.
local util = require("lib.util")

local M = {}

--- Returns the number of worker processes to use: HECATE_TEST_JOBS when it is a positive integer, else the
--- number of cores, at most 4 (the shared runners have 3 or 4 cores).
---@param getenv? fun(name: string): string?
---@param cores? integer
---@return integer
function M.workers(getenv, cores)
  getenv = getenv or os.getenv
  local requested = tonumber(getenv("HECATE_TEST_JOBS") or "")
  if requested and requested >= 1 and requested == math.floor(requested) then return requested end
  if not cores then
    local out = util.is_windows() and (os.getenv("NUMBER_OF_PROCESSORS") or "")
      or util.capture("getconf _NPROCESSORS_ONLN 2>/dev/null")
    cores = tonumber(out) or 1
  end
  return math.max(1, math.min(cores, 4))
end

--- Runs the commands, at most `workers` at a time, and returns { output, ok } per command in command order.
--- `on_start(index)` is called when a command is started (in index order). A command that cannot be started
--- yields ("", false). Output is trimmed of trailing whitespace, as util.capture does.
---@param commands string[]
---@param workers integer
---@param on_start? fun(index: integer)
---@return { output: string, ok: boolean }[]
function M.run(commands, workers, on_start)
  local results, active, started = {}, {}, 0
  local function fill()
    while #active < workers and started < #commands do
      started = started + 1
      if on_start then on_start(started) end
      local command = commands[started]
      -- cmd.exe strips the outer quotes of a command that starts with one (see util.capture).
      if util.is_windows() and command:find('^"') then command = '"' .. command .. '"' end
      active[#active + 1] = { index = started, handle = io.popen(command, "r") }
    end
  end
  fill()
  while #active > 0 do
    local job = table.remove(active, 1)
    if job.handle then
      local out = job.handle:read("a")
      local ok = job.handle:close()
      results[job.index] = { output = (out:gsub("%s+$", "")), ok = ok == true }
    else
      results[job.index] = { output = "", ok = false }
    end
    fill()
  end
  return results
end

return M
