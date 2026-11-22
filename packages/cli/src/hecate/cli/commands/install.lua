-- `hecate install [--frozen]`: installs the dependencies of `hecate.project.lua` into `lua_modules` and writes
-- `hecate.lock` (or, with `--frozen`, installs exactly what it says and verifies it).
global <const> require, error, pairs, ipairs, string

local core = require("hecate.core")

local MANIFEST = "hecate.project.lua"
local LOCK = "hecate.lock"

---@class hecate.cli.InstallDependencies
---@field fs hecate.cli.InstallFileSystem
---@field luarocks hecate.cli.LuaRocks
---@field work_dir string
---@field tree string
---@field sha256? fun(data: string): string  default: the digest backend of the CLI
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)

--- The `install` command.
---@class hecate.cli.commands.install: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.InstallDependencies): integer
local command = {
  name = "install",
  summary = "Install the dependencies of the project and write hecate.lock",
  options = { { name = "frozen", summary = "Install exactly what hecate.lock says and verify it; fail when it is missing or out of date" } },
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

--- The directories to create so that `path` can be written, outermost first, for a relative path, a rooted one
--- (`/home/x/file`) or one with a drive (`C:/Users/x/file`). The root itself and the drive are never listed.
---@param path string  with forward slashes
---@return string[] directories
function command.directories_of(path)
  local directory = path:match("^(.*)/[^/]*$")
  if not directory or directory == "" then return {} end
  local drive = directory:match("^(%a:)")
  local rest = drive and directory:sub(#drive + 1) or directory
  -- `current` starts at the drive, at the root (the empty string, so that the first part is `/part`) or nowhere (relative).
  local current = drive or (rest:sub(1, 1) == "/" and "" or nil)
  local list = {}
  for part in rest:gmatch("[^/]+") do
    current = current == nil and part or (current .. "/" .. part)
    list[#list + 1] = current
  end
  return list
end

--- The real dependencies: the reactor file system and process runner. LuaRocks runs in the work directory for the pin,
--- so every path it receives is absolute, built on the project directory.
---@param runtime hecate.cli.Runtime
---@return hecate.cli.InstallDependencies
local function real_dependencies(runtime)
  local reactor = require("hecate.reactor")
  local runner = require("hecate.cli.runner")
  local luarocks = require("hecate.cli.luarocks")
  local project = (runtime.project_dir or "."):gsub("/+$", "")
  local work_dir, tree = project .. "/.hecate/luarocks", project .. "/lua_modules"

  local function ensure_directory(path)
    for _, directory in ipairs(command.directories_of(path)) do
      if not reactor.fs.stat(directory) then reactor.fs.mkdir(directory) end
    end
  end
  ---@type hecate.cli.InstallFileSystem
  local fs = {
    read = function(path)
      if not reactor.fs.stat(path) then return nil end
      return reactor.fs.read_file(path)
    end,
    write = function(path, text)
      ensure_directory(path)
      reactor.fs.write_file(path, text)
    end,
  }
  return {
    fs = fs,
    work_dir = work_dir,
    tree = tree,
    luarocks = luarocks.new({ runner = runner.run, tree = tree, config_dir = work_dir }),
    run = function(task) return reactor.run(task) end,
  }
end

--- Runs `hecate install` with the real file system, LuaRocks runner and reactor (`execute` takes them as arguments, which
--- is how the tests run it).
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  return command.execute(context, real_dependencies(context.runtime))
end

return command
