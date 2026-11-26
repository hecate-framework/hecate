-- The Lua interpreter that runs the project: a program and the arguments that put it in interpreter mode. With the Lua
-- that runs the `hecate` script, the program is that interpreter and there is no argument; the self-contained executable
-- (ADR 0029) is the interpreter too, started with a leading argument that makes it behave as `lua`.
global <const> ipairs

---@class hecate.cli.internal.interpreter
local M = {}

--- The arguments of a command line for the interpreter: its own leading arguments, then `args`.
---@param leading? string[]  `Runtime.lua_interpreter_arguments`
---@param args string[]
---@return string[] arguments
function M.arguments(leading, args)
  local list = {}
  for _, value in ipairs(leading or {}) do list[#list + 1] = value end
  for _, value in ipairs(args) do list[#list + 1] = value end
  return list
end

return M
