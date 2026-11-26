-- `hecate add <rock>[@constraint] [--dev]`: adds a dependency to `hecate.project.lua`, installs it and updates
-- `hecate.lock`. Without a constraint the one written is `~> major.minor` of the version that was installed.
global <const> require, error, pairs, string

local core = require("hecate.core")
local constraint_module = require("hecate.cli.constraint")
local manifest_edit = require("hecate.cli.manifest_edit")
local manifest_change = require("hecate.cli.internal.manifest_change")
local project_environment = require("hecate.cli.internal.project_environment")

--- The constraint that stands for "any version", used while the real one is not known yet.
local ANY = ">= 0"

--- The `add` command.
---@class hecate.cli.commands.add: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, environment: hecate.cli.ProjectEnvironment): integer
local command = {
  name = "add",
  summary = "Add a dependency to hecate.project.lua, install it and update hecate.lock",
  usage = "<rock>[@constraint]",
  options = { { name = "dev", summary = "Add it to development_dependencies" } },
}

--- `~> major.minor` of an installed version (`0.5-1` gives `~> 0.5`, `1.53.0-0` gives `~> 1.53`, `3-1` gives `~> 3`), nil
--- for a version that is not numeric (`scm-1`, `dev-1`).
---@param version string
---@return string? constraint
function command.default_constraint(version)
  local numbers = version:match("^([%d%.]+)")
  if not numbers then return nil end
  local major, minor = numbers:match("^(%d+)%.(%d+)")
  if major then return "~> " .. major .. "." .. minor end
  local only = numbers:match("^(%d+)%.?$")
  return only and ("~> " .. only) or nil
end

--- Splits the argument `rock@constraint`. Raises `hecate.core.ArgumentError` for an unusable name or constraint.
---@param argument string
---@return string name
---@return string? constraint
function command.split_argument(argument)
  local name, wanted = argument:match("^([^@]*)@(.*)$")
  name = name or argument
  if not name:match("^[%w%._%-]+$") then
    error(core.ArgumentError("'" .. name .. "' is not a rock name (letters, digits, '.', '_' and '-'), for example `hecate add plc` or `hecate add plc@\"~> 0.5\"`"), 0)
  end
  if wanted ~= nil then
    if wanted == "" then error(core.ArgumentError("'" .. argument .. "' has no constraint after '@' (for example `plc@\"~> 0.5\"`)"), 0) end
    constraint_module.parse(wanted)
  end
  return name:lower(), wanted
end

--- Runs the command with the given project environment.
---@param context hecate.cli.Context
---@param environment hecate.cli.ProjectEnvironment
---@return integer exit_code
function command.execute(context, environment)
  if not context.runtime.luarocks_version then
    context.print_error("hecate add: LuaRocks was not found: install LuaRocks 3.x, or run `hecate doctor`")
    return 1
  end
  local positionals = context.arguments.positionals
  if #positionals ~= 1 then
    context.print_error("hecate add: name one rock, for example `hecate add plc` or `hecate add plc@\"~> 0.5\"`")
    return 2
  end
  local name, explicit = command.split_argument(positionals[1])
  local section = context.arguments.options.dev and "development_dependencies" or "dependencies"
  local other = section == "dependencies" and "development_dependencies" or "dependencies"

  local report = environment.run(function()
    return manifest_change.change(context, environment, function(text)
      if manifest_edit.has(text, other, name) then
        error(core.ConfigurationError({ message = "'" .. name .. "' is already in `" .. other .. "`: run `hecate remove " .. name .. "` first to move it" }), 0)
      end
      local planned = manifest_edit.set(text, section, name, explicit or ANY)
      return {
        install_text = planned,
        finish = function(outcome)
          local final_constraint = explicit
          local version
          for locked_name, rock in pairs(outcome.lock.rocks) do
            if locked_name:lower() == name then version = rock.version end
          end
          if not explicit then
            if not version then error(core.ConfigurationError({ message = "LuaRocks did not lock '" .. name .. "'" }), 0) end
            final_constraint = command.default_constraint(version)
            if not final_constraint then
              error(core.ConfigurationError({
                message = "'" .. name .. "' was installed at " .. version .. ", which is not a numbered version: choose the constraint yourself, `hecate add " .. name .. "@\"== " .. version .. "\"`",
              }), 0)
            end
          end
          local final_text = explicit and planned or manifest_edit.set(text, section, name, final_constraint --[[@as string]])
          return final_text, { name = name, constraint = final_constraint, section = section, version = version }
        end,
      }
    end)
  end)
  context.emit(report, string.format("Added %s %s to %s (locked %s); %d rock(s) in hecate.lock", report.name, report.constraint, report.section, report.version or "?", report.locked))
  return 0
end

--- Runs `hecate add` with the real file system, LuaRocks runner and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, project_environment.real(context.runtime))
end

return command
