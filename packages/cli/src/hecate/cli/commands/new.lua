-- `hecate new <name> [--template minimal]`: creates a project directory from a template.
global <const> require, ipairs, pairs, string, table, type, pcall, tostring

local core = require("hecate.core")
local templates = require("hecate.cli.templates")
local project_environment = require("hecate.cli.internal.project_environment")

--- What `new` needs: writing a file (creating the directories) and asking whether a path exists.
---@class hecate.cli.NewDependencies
---@field write fun(path: string, text: string)
---@field exists fun(path: string): boolean
---@field run fun(task: fun(): any): any

--- The `new` command.
---@class hecate.cli.commands.new: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.NewDependencies): integer
local command = {
  name = "new",
  summary = "Create a project from a template",
  usage = "<name> [--template minimal]",
  options = { { name = "template", takes_value = true, summary = "The template: minimal (default)" } },
}

--- Runs the command with the given dependencies.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.NewDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local positionals = context.arguments.positionals
  if #positionals ~= 1 then
    context.print_error("hecate new: name the project, for example `hecate new my-api`")
    return 2
  end
  local name = positionals[1]
  if not name:match("^[a-z0-9][a-z0-9%._%-]*$") then
    context.print_error("hecate new: '" .. name .. "' is not a project name (lower-case letters, digits, '.', '_' and '-'), for example `hecate new my-api`")
    return 2
  end
  local choice = context.arguments.options.template or "minimal"
  local template = type(choice) == "string" and templates.templates[choice]
  if not template then
    context.print_error("hecate new: unknown template '" .. tostring(choice) .. "' (available: " .. table.concat(templates.names(), ", ") .. ")")
    return 2
  end
  local ok, module = pcall(templates.module_name, name)
  if not ok then
    context.print_error("hecate new: " .. (type(module) == "table" and module.message or tostring(module)))
    return 2
  end

  local version = context.runtime.hecate_version:match("^(%d+%.%d+)") or "0.1"
  local files = template({ name = name, module = module, hecate_constraint = "~> " .. version })
  local paths = {}
  for path in pairs(files) do paths[#paths + 1] = path end
  table.sort(paths)

  local code = dependencies.run(function()
    if dependencies.exists(name) then
      context.print_error("hecate new: '" .. name .. "' already exists; choose another name or remove it")
      return 1
    end
    for _, path in ipairs(paths) do dependencies.write(name .. "/" .. path, files[path]) end
    return 0
  end)
  if code ~= 0 then return code end
  context.emit({ name = name, template = choice, files = paths },
    string.format("Created %s from the %s template (%d files).\nNext: cd %s && hecate install && hecate serve", name, choice, #paths, name))
  return 0
end

--- Runs `hecate new` with the real file system and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local environment = project_environment.real(context.runtime)
  local reactor = require("hecate.reactor")
  return command.execute(context, {
    write = environment.fs.write,
    exists = function(path) return reactor.fs.stat(path) ~= nil end,
    run = environment.run,
  })
end

return command
