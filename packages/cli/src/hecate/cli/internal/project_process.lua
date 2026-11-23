-- Running a Lua program in the interpreter of the project, with its module path (`src`, the root, `lua_modules`): the way the
-- CLI uses the rocks of the project (`hecate.openapi`, `hecate.doc`, ...) without loading them in its own process (owner
-- decision of 2026-11-23: the executable bundles only what the CLI itself needs). The program gets its input through
-- environment variables and files, and writes its result on standard output.
global <const> require, error, pairs

local core = require("hecate.core")
local interpreter = require("hecate.cli.internal.interpreter")
local serve_command = require("hecate.cli.commands.serve")

---@class hecate.cli.internal.project_process
local M = {}

---@class hecate.cli.ProcessDependencies
---@field run_process fun(program: string, args: string[], options: table): hecate.cli.ProcessResult
---@field interpreter string
---@field interpreter_arguments? string[]

---@class hecate.cli.ProcessResult
---@field code integer
---@field stdout string
---@field stderr string

--- The error for a program that failed: what it wrote on standard error, with the advice that fits a rock of the project
--- that cannot be found (`hecate install` puts it in `lua_modules`).
---@param result hecate.cli.ProcessResult
---@param what string  what the program was doing, for the first line
---@return hecate.core.Error
function M.failure(result, what)
  local detail = result.stderr ~= "" and (result.stderr:gsub("%s+$", "")) or ("the process exited with " .. result.code)
  local missing = detail:match("module '(hecate[%w_%.]*)' not found")
  local advice = ""
  if missing then
    -- The list of the files searched is long and says nothing the advice does not.
    detail = detail:match("^[^\n]*")
    advice = "\n'" .. missing .. "' is a rock of the project: run `hecate install` in the project directory (the project depends on `hecate`)"
  end
  return core.ConfigurationError({ message = what .. " failed:\n" .. detail .. advice, context = { code = result.code } })
end

--- Runs `program` (Lua source) in the interpreter of the project, in the project directory, and returns its result. Suspends
--- (`run_process` of the reactor). Raises `hecate.core.ConfigurationError` when the program exits with a status other than 0.
---@async
---@param context hecate.cli.Context
---@param dependencies table  with the fields of `hecate.cli.ProcessDependencies`
---@param program string
---@param extra_environment? table<string, string>
---@param what string  for the error message
---@return hecate.cli.ProcessResult result
function M.run(context, dependencies, program, extra_environment, what)
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local lua = context.runtime.lua_version:match("^%d+%.%d+") or context.runtime.lua_version
  local env = serve_command.environment(project, lua)
  for name, value in pairs(extra_environment or {}) do env[name] = value end
  local result = dependencies.run_process(dependencies.interpreter, interpreter.arguments(dependencies.interpreter_arguments, { "-e", program }), { env = env, cwd = project })
  if result.code ~= 0 then error(M.failure(result, what), 0) end
  return result
end

return M
