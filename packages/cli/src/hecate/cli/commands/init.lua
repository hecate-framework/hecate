-- `hecate init [--name <name>]`: adds Hecate to the current directory with the minimal template, keeping every file
-- that already exists.
global <const> require, os, ipairs, pairs, string, table, pcall, type, tostring

local templates = require("hecate.cli.templates")
local project_environment = require("hecate.cli.internal.project_environment")

--- What `init` needs: writing and probing files (relative to the current directory), and the directory's name.
---@class hecate.cli.InitDependencies
---@field write fun(path: string, text: string)
---@field exists fun(path: string): boolean
---@field directory_name fun(): string
---@field run fun(task: fun(): any): any

--- The `init` command.
---@class hecate.cli.commands.init: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.InitDependencies): integer
local command = {
  name = "init",
  summary = "Add Hecate to the current directory",
  usage = "[--name <name>]",
  options = { { name = "name", takes_value = true, summary = "The project name (default: the directory name)" } },
}

--- Runs the command with the given dependencies.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.InitDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  if #context.arguments.positionals ~= 0 then
    context.print_error("hecate init: takes no argument; to create a new directory use `hecate new <name>`")
    return 2
  end
  local name = context.arguments.options.name
  if name == nil then name = dependencies.run(dependencies.directory_name) end
  if type(name) ~= "string" or not name:match("^[a-z0-9][a-z0-9%._%-]*$") then
    context.print_error("hecate init: '" .. tostring(name) .. "' is not a project name (lower-case letters, digits, '.', '_' and '-'); pass one with `--name my-api`")
    return 2
  end
  local ok, module = pcall(templates.module_name, name)
  if not ok then
    context.print_error("hecate init: " .. (type(module) == "table" and module.message or tostring(module)))
    return 2
  end

  local version = context.runtime.hecate_version:match("^(%d+%.%d+)") or "0.1"
  local files = templates.templates.minimal({ name = name, module = module, hecate_constraint = "~> " .. version })
  local paths = {}
  for path in pairs(files) do paths[#paths + 1] = path end
  table.sort(paths)

  local created, kept = {}, {}
  local code = dependencies.run(function()
    if dependencies.exists("hecate.project.lua") then
      context.print_error("hecate init: hecate.project.lua already exists here; this directory is already a Hecate project")
      return 1
    end
    for _, path in ipairs(paths) do
      if dependencies.exists(path) then
        kept[#kept + 1] = path
      else
        dependencies.write(path, files[path])
        created[#created + 1] = path
      end
    end
    return 0
  end)
  if code ~= 0 then return code end
  local text = string.format("Initialised %s (%d files created", name, #created)
  if #kept > 0 then text = text .. ", " .. #kept .. " kept: " .. table.concat(kept, ", ") end
  context.emit({ name = name, created = created, kept = kept }, text .. ").\nNext: hecate install && hecate serve --env development")
  return 0
end

--- Runs `hecate init` in the current directory with the real file system and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local environment = project_environment.real(context.runtime)
  local reactor = require("hecate.reactor")
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  return command.execute(context, {
    write = function(path, text) environment.fs.write(project .. "/" .. path, text) end,
    exists = function(path) return reactor.fs.stat(project .. "/" .. path) ~= nil end,
    directory_name = function()
      -- A relative project directory names nothing: ask the shell's working directory (PWD, or CD on Windows).
      local real = (project == "" or project == ".") and (os.getenv("PWD") or os.getenv("CD") or "") or project
      return (real:gsub("\\", "/"):match("([^/]+)/*$") or "")
    end,
    run = environment.run,
  })
end

return command
