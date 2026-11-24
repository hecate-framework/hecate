-- `hecate install [--frozen]`: installs the dependencies of `hecate.project.lua` into `lua_modules` and writes
-- `hecate.lock` (or, with `--frozen`, installs exactly what it says and verifies it).
global <const> require, error, pairs, string

local core = require("hecate.core")
local project_environment = require("hecate.cli.internal.project_environment")

local MANIFEST = "hecate.project.lua"
local LOCK = "hecate.lock"

---@alias hecate.cli.InstallDependencies hecate.cli.ProjectEnvironment

--- The `install` command.
---@class hecate.cli.commands.install: hecate.cli.Command
---@field directories_of fun(path: string): string[]
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.InstallDependencies): integer
local command = {
  name = "install",
  summary = "Install the dependencies of the project and write hecate.lock",
  options = { { name = "frozen", summary = "Install exactly what hecate.lock says and verify it; fail when it is missing or out of date" } },
  directories_of = project_environment.directories_of,
}

--- Runs the command with the given file system, LuaRocks and task runner.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.InstallDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local runtime = context.runtime
  if not runtime.luarocks_version then
    context.print_error("hecate install: LuaRocks was not found: install LuaRocks 3.x, or run `hecate doctor`")
    return 1
  end
  local frozen = context.arguments.options.frozen == true
  local fs = dependencies.fs
  local result = dependencies.run(function()
    local manifest_text = fs.read(MANIFEST)
    if manifest_text == nil then
      error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
    end
    local installer = require("hecate.cli.installer")
    local outcome = installer.install({
      manifest_text = manifest_text,
      lock_text = fs.read(LOCK),
      frozen = frozen,
      fs = fs,
      luarocks = dependencies.luarocks,
      work_dir = dependencies.work_dir,
      tree = dependencies.tree,
      sha256 = dependencies.sha256,
      lua_headers = dependencies.lua_headers,
      lua = runtime.lua_version,
      luarocks_version = runtime.luarocks_version --[[@as string]],
    })
    if not frozen then fs.write(LOCK, outcome.lock_text) end
    return outcome
  end)
  local count = 0
  for _ in pairs(result.lock.rocks) do count = count + 1 end
  context.emit({ frozen = frozen, installed = result.installed, locked = count, lockfile = LOCK },
    string.format("Installed %d rock(s) into %s; %s %s", result.installed, dependencies.tree, LOCK, frozen and "verified" or "written"))
  return 0
end

--- Runs `hecate install` with the real file system, LuaRocks runner and reactor (`execute` takes them as arguments, which
--- is how the tests run it).
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, project_environment.real(context.runtime))
end

return command
