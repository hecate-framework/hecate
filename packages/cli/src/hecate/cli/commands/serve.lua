-- `hecate serve [--watch] [--workers N]`: runs the application of the project (`main.lua`) in a child process (OQ-132),
-- with the dependencies of `lua_modules` and the sources on its module path. It forwards `sigint` and `sigterm` (the
-- child stops gracefully, `hecate serve` never daemonises, OQ-133), forwards `sighup` (a primary reloads, ADR 0023),
-- returns the exit code of the child, and with `--watch` restarts the child when a source file changes.
global <const> require, error, package, table, tonumber, math, pcall

local core = require("hecate.core")
local serve = require("hecate.cli.serve")
local tests = require("hecate.cli.commands.tests")
local interpreter = require("hecate.cli.internal.interpreter")

local MANIFEST = "hecate.project.lua"
local ENTRY = "main.lua"

---@class hecate.cli.ServeDependencies
---@field exists fun(path: string): boolean  whether a file exists (called inside `run`)
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)
---@field reactor hecate.cli.ServeReactor|table  the reactor: `scope`, `select`, `sleep`, `deadline`, `spawn`, `watch_signals`, `fs`
---@field interpreter string  the Lua interpreter that runs the project
---@field interpreter_arguments? string[]  the arguments that put it in interpreter mode
---@field windows boolean

--- The `serve` command.
---@class hecate.cli.commands.serve: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.ServeDependencies): integer
local command = {
  name = "serve",
  summary = "Run the application of the project (main.lua); with --watch, restart it when the sources change",
  options = {
    { name = "watch", summary = "Restart the application when a .lua file of src, config or main.lua changes" },
    { name = "workers", takes_value = true, summary = "Number of worker processes (a number, or auto); sets HECATE_SERVER__WORKERS for the application" },
  },
}

--- The environment of the child: the module paths of the project (Lua 5.5 reads `LUA_PATH_5_5` first, then `LUA_PATH`; the
--- trailing `;;` keeps the defaults) and, when given, the number of workers.
---@param project string  absolute path, forward slashes
---@param lua string  the Lua line (`5.5`)
---@param workers? string
---@return table<string, string> env
function command.environment(project, lua, workers)
  local lua_paths, native_paths = tests.module_paths(project, lua)
  local path = table.concat(lua_paths, ";") .. ";;"
  local cpath = table.concat(native_paths, ";") .. ";;"
  local env = { LUA_PATH = path, LUA_PATH_5_5 = path, LUA_CPATH = cpath, LUA_CPATH_5_5 = cpath }
  if workers then env.HECATE_SERVER__WORKERS = workers end
  return env
end

--- Whether `--workers` holds a valid value: a positive whole number or `auto`.
---@param value string
---@return boolean
function command.valid_workers(value)
  if value == "auto" then return true end
  local number = tonumber(value)
  return number ~= nil and math.type(number) == "integer" and number >= 1
end

--- Runs the command with the given reactor and file system.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.ServeDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local options = context.arguments.options
  local workers = options.workers --[[@as string?]]
  if workers ~= nil and not command.valid_workers(workers) then
    context.print_error("hecate serve: --workers takes a whole number of at least 1, or auto (got '" .. workers .. "')")
    return 2
  end
  if #context.arguments.positionals > 0 then
    context.print_error("hecate serve: takes no argument (it runs " .. ENTRY .. "); got '" .. context.arguments.positionals[1] .. "'")
    return 2
  end
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local lua = context.runtime.lua_version:match("^%d+%.%d+") or context.runtime.lua_version
  local watching = options.watch == true
  local reactor = dependencies.reactor

  return dependencies.run(function()
    if not dependencies.exists(project .. "/" .. MANIFEST) then
      error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
    end
    if not dependencies.exists(project .. "/" .. ENTRY) then
      error(core.ConfigurationError({ message = ENTRY .. " not found: `hecate serve` runs it; create it, or run `hecate new <name>` for a project that has one" }), 0)
    end
    local names = { "sigint", "sigterm" }
    if not dependencies.windows then names[#names + 1] = "sighup" end
    local signals = reactor.watch_signals(table.unpack(names))
    local env = command.environment(project, lua, workers)
    local roots = { project .. "/src", project .. "/config", project .. "/" .. ENTRY }
    local ok, result = pcall(serve.supervise, reactor, {
      start = function()
        context.print_error("hecate serve: starting " .. ENTRY)
        return reactor.spawn(dependencies.interpreter, interpreter.arguments(dependencies.interpreter_arguments, { ENTRY }), { env = env, cwd = project }) -- glossary-ok: an operating-system process
      end,
      signals = signals,
      changes = watching and function() return serve.poll_changes(reactor, reactor.fs, roots) end or nil,
      say = function(text) context.print_error("hecate serve: " .. text) end,
    })
    signals:close()
    if not ok then error(result, 0) end
    return result
  end)
end

--- Runs `hecate serve` with the real reactor, the interpreter that runs this process and the current directory.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local reactor = require("hecate.reactor")
  return command.execute(context, {
    exists = function(path) return reactor.fs.stat(path) ~= nil end,
    run = function(task) return reactor.run(task) end,
    reactor = reactor,
    interpreter = context.runtime.lua_interpreter or "lua",
    interpreter_arguments = context.runtime.lua_interpreter_arguments,
    windows = package.config:sub(1, 1) == "\\",
  })
end

return command
