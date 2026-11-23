-- `hecate run <script> [-- <arguments>...]`: runs a Lua script of the project in the project environment: a script
-- declared in `scripts` of `hecate.project.lua` (by name), or a `.lua` file of the project (by path). It runs in a child
-- process of the interpreter that runs `hecate`, in the project directory, with the module path of `hecate serve`; the
-- exit code of the script is the one of `hecate run`.
global <const> require, error, pairs, package, table, pcall

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local serve = require("hecate.cli.serve")
local serve_command = require("hecate.cli.commands.serve")
local interpreter = require("hecate.cli.internal.interpreter")

local MANIFEST = "hecate.project.lua"

---@class hecate.cli.RunDependencies
---@field read fun(path: string): string?  the text of a file, nil when it does not exist (called inside `run`)
---@field exists fun(path: string): boolean
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)
---@field reactor table  the reactor: `scope`, `select`, `sleep`, `deadline`, `spawn`, `watch_signals`
---@field interpreter string
---@field interpreter_arguments? string[]
---@field windows boolean

--- The `run` command.
---@class hecate.cli.commands.run: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.RunDependencies): integer
local command = {
  name = "run",
  summary = "Run a script of the project: a name from `scripts` of the manifest, or a .lua file",
  usage = "<script> [-- <arguments>...]",
}

--- Whether a path stays inside the project: relative, no `..` segment, not a drive or a root.
---@param path string
---@return boolean
function command.inside_project(path)
  if path == "" or path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" or path:match("^%a:") then return false end
  for segment in path:gmatch("[^/\\]+") do
    if segment == ".." then return false end
  end
  return true
end

--- The file that `target` stands for: the script of that name in the manifest, else `target` itself when it is a `.lua`
--- path. Returns nil and a message when it is neither.
---@param manifest hecate.cli.Manifest
---@param target string
---@return string? path
---@return string? message
function command.resolve(manifest, target)
  local declared = (manifest.scripts or {})[target]
  if declared then return declared end
  if target:match("%.lua$") then return target end
  local names = {}
  for name in pairs(manifest.scripts or {}) do names[#names + 1] = name end
  table.sort(names)
  return nil, "'" .. target .. "' is not a script of hecate.project.lua"
    .. (#names > 0 and (" (scripts: " .. table.concat(names, ", ") .. ")") or " (it declares no `scripts`)")
    .. ", and not the path of a .lua file"
end

--- Runs the command with the given file system and reactor.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.RunDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local positionals = context.arguments.positionals
  if #positionals == 0 then
    context.print_error("hecate run: name a script of hecate.project.lua or a .lua file, for example `hecate run seed`; arguments for it follow `--`: `hecate run seed -- --count 5`")
    return 2
  end
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local lua = context.runtime.lua_version:match("^%d+%.%d+") or context.runtime.lua_version
  local reactor = dependencies.reactor

  return dependencies.run(function()
    local text = dependencies.read(project .. "/" .. MANIFEST)
    if text == nil then
      error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
    end
    local manifest = manifest_module.parse(text)
    local script, message = command.resolve(manifest, positionals[1])
    if not script then error(core.ConfigurationError({ message = message }), 0) end
    if not command.inside_project(script) then
      error(core.ConfigurationError({ message = "'" .. script .. "' leaves the project: a script is a relative path inside the project directory" }), 0)
    end
    if not dependencies.exists(project .. "/" .. script) then
      error(core.ConfigurationError({ message = script .. " not found in the project" }), 0)
    end

    local arguments = { script }
    for index = 2, #positionals do arguments[#arguments + 1] = positionals[index] end
    local names = { "sigint", "sigterm" }
    local signals = reactor.watch_signals(table.unpack(names))
    local env = serve_command.environment(project, lua)
    local ok, result = pcall(serve.supervise, reactor, {
      start = function()
        return reactor.spawn(dependencies.interpreter, interpreter.arguments(dependencies.interpreter_arguments, arguments), { env = env, cwd = project }) -- glossary-ok: an operating-system process
      end,
      signals = signals,
    })
    signals:close()
    if not ok then error(result, 0) end
    return result
  end)
end

--- Runs `hecate run` with the real reactor, the interpreter that runs this process and the current directory.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local reactor = require("hecate.reactor")
  return command.execute(context, {
    read = function(path)
      if not reactor.fs.stat(path) then return nil end
      return reactor.fs.read_file(path)
    end,
    exists = function(path) return reactor.fs.stat(path) ~= nil end,
    run = function(task) return reactor.run(task) end,
    reactor = reactor,
    interpreter = context.runtime.lua_interpreter or "lua",
    interpreter_arguments = context.runtime.lua_interpreter_arguments,
    windows = package.config:sub(1, 1) == "\\",
  })
end

return command
