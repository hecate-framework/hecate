-- Runs a chunk of Lua that describes data (`site.lua`, a rockspec) with limits on the work it may do: a count of
-- instructions and growth of the memory of the process, both checked by a hook of the coroutine that runs it.
--
-- What this bounds: loops and recursion in Lua code (`while true do end`), and allocation that goes through Lua
-- instructions (a table filled in a loop, a string built by `..` in a loop). What it does not bound: one call into C that
-- allocates by itself, such as `("x"):rep(1e10)` (the string metatable stays reachable from any string, whatever the
-- environment), which no hook can interrupt. The callers close the other doors (an empty environment, no call at all for a
-- rockspec): this module is a guard against a mistake and against runaway loops, not a security boundary against a
-- hostile `site.lua`, which is code of the project and runs with its privileges.
global <const> require, coroutine, debug, collectgarbage, error, tostring, type

local M = {}

--- The default limits: instructions (a `site.lua` of a few hundred lines needs a few thousand) and kilobytes of growth.
M.INSTRUCTIONS = 1000000
M.KILOBYTES = 16 * 1024

local STEP = 1000 -- instructions between two checks of the hook

--- Runs `chunk` (a function) in a coroutine with the limits. Returns `true` and what it returns, or `false` and the
--- message of the error (`instruction limit`, `memory limit`, or the error of the chunk).
---@param chunk function
---@param limits? { instructions?: integer, kilobytes?: integer }
---@return boolean ok
---@return any result
function M.run(chunk, limits)
  limits = limits or {}
  local instructions = limits.instructions or M.INSTRUCTIONS
  local kilobytes = limits.kilobytes or M.KILOBYTES
  local thread = coroutine.create(chunk)
  local baseline = collectgarbage("count")
  local steps = 0
  debug.sethook(thread, function()
    steps = steps + 1
    if steps * STEP > instructions then error("instruction limit", 0) end
    if collectgarbage("count") - baseline > kilobytes then error("memory limit", 0) end
  end, "", STEP)
  local ok, result = coroutine.resume(thread)
  if ok and coroutine.status(thread) ~= "dead" then return false, "the chunk yielded" end
  if not ok and type(result) ~= "string" then result = tostring(result) end
  return ok, result
end

return M
