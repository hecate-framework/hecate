-- `hecate outdated`: the rocks of the project that have a newer version on the servers, and whether the constraint of
-- the manifest lets `hecate update` take it.
global <const> require, error, ipairs, string, table

local core = require("hecate.core")
local constraint = require("hecate.cli.constraint")
local manifest_module = require("hecate.cli.manifest")
local project_environment = require("hecate.cli.internal.project_environment")

local MANIFEST = "hecate.project.lua"

---@alias hecate.cli.OutdatedDependencies hecate.cli.ProjectEnvironment

--- The `outdated` command.
---@class hecate.cli.commands.outdated: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.OutdatedDependencies): integer
local command = {
  name = "outdated",
  summary = "List the rocks that have a newer version, and whether the manifest allows it",
}

--- What the constraint of the manifest says about a newer version: `update` (it fits: `hecate update <rock>` takes it),
--- `constraint` (the manifest excludes it: edit the constraint) or `indirect` (a dependency of a dependency, not
--- constrained by this manifest).
---@param manifest hecate.cli.Manifest
---@param rock hecate.cli.OutdatedRock
---@return string status
---@return string? wanted  the constraint of the manifest, when the rock is a direct dependency
local function status_of(manifest, rock)
  local wanted = (manifest.dependencies or {})[rock.name] or (manifest.development_dependencies or {})[rock.name]
  if wanted == nil then return "indirect", nil end
  if constraint.satisfies(rock.available, wanted) then return "update", wanted end
  return "constraint", wanted
end

--- Runs the command with the given file system, LuaRocks and task runner.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.OutdatedDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  if not context.runtime.luarocks_version then
    context.print_error("hecate outdated: LuaRocks was not found: install LuaRocks 3.x, or run `hecate doctor`")
    return 1
  end
  -- The file system and LuaRocks suspend: everything that touches them runs inside the reactor.
  local found = dependencies.run(function()
    local text = dependencies.fs.read(MANIFEST)
    if text == nil then
      error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
    end
    local parsed = manifest_module.parse(text)
    return { manifest = parsed, list = dependencies.luarocks:outdated() }
  end)
  local manifest, list = found.manifest, found.list

  local rows, lines = {}, {}
  for _, rock in ipairs(list) do
    local status, wanted = status_of(manifest, rock)
    rows[#rows + 1] = { name = rock.name, installed = rock.installed, available = rock.available, constraint = wanted, status = status }
    local note = status == "update" and "within " .. wanted
      or status == "constraint" and "excluded by " .. wanted
      or "indirect"
    lines[#lines + 1] = string.format("%-24s %-14s -> %-14s %s", rock.name, rock.installed, rock.available, note)
  end
  context.emit({ outdated = rows }, #rows == 0 and "All rocks are up to date." or table.concat(lines, "\n"))
  return 0
end

--- Runs `hecate outdated` with the real file system, LuaRocks runner and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, project_environment.real(context.runtime))
end

return command
