-- The real runner of the CLI: runs a program through the reactor and answers in the shape `hecate.cli.luarocks`
-- expects. It suspends, so it runs inside a reactor.
global <const> require

local reactor = require("hecate.reactor")

--- Running programs for the commands of the CLI.
---@class hecate.cli.runner
local M = {}

--- Runs `program` to completion with the environment and working directory of `options`, capturing its output.
--- Suspends. `code` is the exit status; a child ended by a signal reports the code of the reactor (on Windows 1).
---@async
---@param program string
---@param args string[]
---@param options hecate.cli.RunOptions
---@return hecate.cli.RunResult result
function M.run(program, args, options)
  local result = reactor.run_process(program, args, { env = options.env, cwd = options.cwd })
  return { code = result.code, stdout = result.stdout, stderr = result.stderr }
end

return M
