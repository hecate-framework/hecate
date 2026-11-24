-- `hecate update [<rock>]`: installs again, taking the newest versions that the constraints of `hecate.project.lua`
-- allow, and writes `hecate.lock`.
global <const> require, error, ipairs, pairs, string, table

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local project_environment = require("hecate.cli.internal.project_environment")

local MANIFEST = "hecate.project.lua"
local LOCK = "hecate.lock"

--- The `update` command.
---@class hecate.cli.commands.update: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, environment: hecate.cli.ProjectEnvironment): integer
local command = {
  name = "update",
  summary = "Take the newest versions the constraints allow and rewrite hecate.lock",
  usage = "[<rock>]",
}

---@param context hecate.cli.Context
---@param environment hecate.cli.ProjectEnvironment
---@return integer exit_code
function command.execute(context, environment)
  local runtime = context.runtime
  if not runtime.luarocks_version then
    context.print_error("hecate update: LuaRocks was not found: install LuaRocks 3.x, or run `hecate doctor`")
    return 1
  end
  local positionals = context.arguments.positionals
  if #positionals > 1 then
    context.print_error("hecate update: name at most one rock, for example `hecate update plc`")
    return 2
  end
  local only = positionals[1] and positionals[1]:lower() or nil
  local fs = environment.fs
  local found = environment.run(function()
    local text = fs.read(MANIFEST)
    if text == nil then
      error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
    end
    if only then
      local manifest = manifest_module.parse(text)
      if (manifest.dependencies or {})[only] == nil and (manifest.development_dependencies or {})[only] == nil then
        error(core.ConfigurationError({ message = "'" .. only .. "' is not a direct dependency in " .. MANIFEST .. ": `hecate update` without argument updates everything" }), 0)
      end
    end
    local old = fs.read(LOCK)
    local outcome = require("hecate.cli.installer").install({
      manifest_text = text,
      lock_text = old,
      refresh = only and { only } or {},
      fs = fs,
      luarocks = environment.luarocks,
      work_dir = environment.work_dir,
      tree = environment.tree,
      sha256 = environment.sha256,
      lua_headers = environment.lua_headers,
      lua = runtime.lua_version,
      luarocks_version = runtime.luarocks_version --[[@as string]],
    })
    fs.write(LOCK, outcome.lock_text)
    return { outcome = outcome, before = old and require("hecate.cli.lockfile").parse(old) or nil }
  end)
  local result, before = found.outcome, found.before

  local changes = {}
  for name, record in pairs(result.lock.rocks) do
    local was = before and before.rocks[name]
    if not was then changes[#changes + 1] = { name = name, from = nil, to = record.version }
    elseif was.version ~= record.version then changes[#changes + 1] = { name = name, from = was.version, to = record.version } end
  end
  table.sort(changes, function(a, b) return a.name < b.name end)
  local lines = {}
  for _, change in ipairs(changes) do
    lines[#lines + 1] = string.format("  %s %s -> %s", change.name, change.from or "(new)", change.to)
  end
  context.emit({ updated = changes, lockfile = LOCK },
    #changes == 0 and ("Nothing to update; " .. LOCK .. " rewritten")
      or string.format("Updated %d rock(s); %s written\n%s", #changes, LOCK, table.concat(lines, "\n")))
  return 0
end

---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, project_environment.real(context.runtime))
end

return command
