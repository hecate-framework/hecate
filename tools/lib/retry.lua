-- Retry of a step that reaches the network (a git fetch of a pinned commit): a transient failure
-- of a remote endpoint is not a verdict on the repository. Standard library only.
local util = require("lib.util")
local M = {}

--- Waits `seconds` (whole seconds) without a busy loop, on Windows and Unix.
---@param seconds integer
function M.pause(seconds)
  if seconds <= 0 then return end
  if util.is_windows() then
    os.execute(("ping -n %d 127.0.0.1 >nul"):format(seconds + 1))
  else
    os.execute(("sleep %d"):format(seconds))
  end
end

--- Calls `step()` (returning `output, ok`) up to `tries` times, pausing `pause_seconds` between tries;
--- returns the result of the last call. `pause` is injectable for tests.
---@param step fun(): string, boolean
---@param tries? integer  default 3
---@param pause_seconds? integer  default 5
---@param pause? fun(seconds: integer)
---@return string output
---@return boolean ok
---@return integer used  number of tries made
function M.run(step, tries, pause_seconds, pause)
  tries = tries or 3
  pause = pause or M.pause
  local out, ok
  for attempt = 1, tries do
    out, ok = step()
    if ok then return out, true, attempt end
    if attempt < tries then pause(pause_seconds or 5) end
  end
  return out, false, tries
end

return M
