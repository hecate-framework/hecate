-- `hecate remove <rock>`: removes a dependency from `hecate.project.lua` and updates `hecate.lock`.
global <const> require, error, ipairs, string

local core = require("hecate.core")
local manifest_edit = require("hecate.cli.manifest_edit")
local manifest_change = require("hecate.cli.internal.manifest_change")
local project_environment = require("hecate.cli.internal.project_environment")

--- The `remove` command.
---@class hecate.cli.commands.remove: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, environment: hecate.cli.ProjectEnvironment): integer
local command = {
  name = "remove",
  summary = "Remove a dependency from hecate.project.lua and update hecate.lock",
  usage = "<rock>",
}

--- Runs the command with the given project environment.
---@param context hecate.cli.Context
---@param environment hecate.cli.ProjectEnvironment
---@return integer exit_code
function command.execute(context, environment)
  if not context.runtime.luarocks_version then
    context.print_error("hecate remove: LuaRocks was not found: install LuaRocks 3.x, or run `hecate doctor`")
    return 1
  end
  local positionals = context.arguments.positionals
  if #positionals ~= 1 then
    context.print_error("hecate remove: name one rock, for example `hecate remove plc`")
    return 2
  end
  local name = positionals[1]:lower()

  local report = environment.run(function()
    return manifest_change.change(context, environment, function(text)
      local section
      for _, candidate in ipairs(manifest_edit.SECTIONS) do
        if manifest_edit.has(text, candidate, name) then section = candidate break end
      end
      if not section then
        error(core.ConfigurationError({ message = "'" .. name .. "' is not a dependency in hecate.project.lua (see `dependencies` and `development_dependencies`)" }), 0)
      end
      local final_text = manifest_edit.remove(text, section, name)
      return { install_text = final_text, finish = function() return final_text, { name = name, section = section } end }
    end)
  end)
  context.emit(report, string.format("Removed %s from %s; %d rock(s) in hecate.lock (its files stay in the tree until you delete lua_modules)", report.name, report.section, report.locked))
  return 0
end

--- Runs `hecate remove` with the real file system, LuaRocks runner and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, project_environment.real(context.runtime))
end

return command
