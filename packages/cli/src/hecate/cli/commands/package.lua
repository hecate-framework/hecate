-- `hecate package [--output <file>]`: the release archive of the project, for a server without Docker (cli-and-packaging.md,
-- "Delivery to a server"): `hecate.project.lua`, `hecate.lock`, `main.lua`, `src/`, `config/` and `lua_modules/` (what
-- `hecate install --frozen` gave), a `RELEASE` file (project version, Hecate version, Lua release, platform) and a `.sha256` next to
-- the archive. Tests, `.git`, `.hecate/` and the documentation site stay out. The archive is `<name>-<version>-<platform>.tar.gz`
-- (a `.zip` on Windows), written in the directory of the project unless `--output` says otherwise.
global <const> require, error, ipairs, string, table, os, type, tostring, package

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")

local MANIFEST = "hecate.project.lua"
local LOCK = "hecate.lock"
--- What goes into the archive when it exists, in this order; the first three are required.
local CONTENT = { MANIFEST, LOCK, "main.lua", "src", "config", "lua_modules" }
local REQUIRED = { [MANIFEST] = true, [LOCK] = true, ["main.lua"] = true, src = true }

---@class hecate.cli.PackageFileSystem  what the command does inside `run` (the reactor): the file system calls suspend
---@field read fun(path: string): string?
---@field exists fun(path: string): boolean
---@field write fun(path: string, text: string)
---@field remove fun(path: string)

---@class hecate.cli.PackageDependencies
---@field fs hecate.cli.PackageFileSystem
---@field run fun(task: fun(): any): any
---@field run_process fun(program: string, args: string[], options: table): { code: integer, stdout: string, stderr: string }
---@field sha256_file fun(path: string): string?, string?
---@field tar string  the program that writes archives (`tar`; on Windows the one of System32)
---@field windows boolean

--- The text of the `RELEASE` file.
---@param manifest hecate.cli.Manifest
---@param runtime hecate.cli.Runtime
---@return string text
local function release_text(manifest, runtime)
  return table.concat({
    "name = " .. manifest.name,
    "version = " .. tostring(manifest.version),
    "hecate = " .. runtime.hecate_version,
    "lua = " .. runtime.lua_version,
    "platform = " .. runtime.platform,
    "",
  }, "\n")
end

--- The `package` command.
---@class hecate.cli.commands.package: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.PackageDependencies): integer
local command = {
  name = "package",
  summary = "Write the release archive of the project (for a server without Docker)",
  options = {
    { name = "output", takes_value = true, summary = "Write the archive here (default: <name>-<version>-<platform>.tar.gz in the project)" },
  },
}

--- Runs the command.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.PackageDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local text = dependencies.run(function() return (dependencies.fs.read(project .. "/" .. MANIFEST)) end)
  if text == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local manifest = manifest_module.parse(text)
  local version = manifest.version or "0.0.0"
  local default_name = ("%s-%s-%s.%s"):format(manifest.name, version, context.runtime.platform, dependencies.windows and "zip" or "tar.gz")
  local output = context.arguments.options.output --[[@as string?]] or (project .. "/" .. default_name)
  -- The format comes from the name: bsdtar (`-a`, Windows) reads it from the suffix, and a name that says otherwise
  -- than what is written would mislead whoever unpacks it.
  local lowered = output:lower()
  local suffix_ok = lowered:match("%.tar%.gz$") or lowered:match("%.tgz$") or (dependencies.windows and lowered:match("%.zip$"))
  if not suffix_ok then
    context.print_error("hecate package: --output must end in " .. (dependencies.windows and ".zip, .tar.gz or .tgz" or ".tar.gz or .tgz") .. " (got '" .. output .. "')")
    return 2
  end
  -- GNU tar reads `host:path` as a file on another machine (and may start `rsh`): a relative name is anchored with `./`.
  if not dependencies.windows and not output:match("^/") then output = "./" .. output end
  return dependencies.run(function()
    if dependencies.windows and not dependencies.fs.exists(dependencies.tar) then
      context.print_error("hecate package: " .. dependencies.tar .. " was not found: Windows 10 (1803) and later ship it; install it, or write the archive with another tool")
      return 1
    end
    local content = {}
    for _, name in ipairs(CONTENT) do
      if dependencies.fs.exists(project .. "/" .. name) then content[#content + 1] = name
      elseif REQUIRED[name] then
        local advice = name == LOCK and "run `hecate install` and commit hecate.lock" or "the project must have it"
        context.print_error("hecate package: " .. name .. " not found in the project: " .. advice)
        return 1
      end
    end
    if not dependencies.fs.exists(project .. "/lua_modules") then
      context.print_error("hecate package: lua_modules/ not found: run `hecate install --frozen` first, on the platform of the server")
      return 1
    end
    -- RELEASE is written next to the content for the archive, and removed after it.
    dependencies.fs.write(project .. "/RELEASE", release_text(manifest, context.runtime))
    local arguments = { dependencies.windows and "-a" or "-z", "-c", "-f", output, "-C", project, "RELEASE" }
    for _, name in ipairs(content) do arguments[#arguments + 1] = name end
    local result = dependencies.run_process(dependencies.tar, arguments, { cwd = project, env = { COPYFILE_DISABLE = "1" } }) -- macOS: no `._*` AppleDouble files in the archive
    dependencies.fs.remove(project .. "/RELEASE")
    if result.code ~= 0 then
      context.print_error("hecate package: the archive was not written (" .. dependencies.tar .. " exited with " .. result.code .. "):\n"
        .. (result.stderr:gsub("%s+$", "")))
      return 1
    end
    local sum, message = dependencies.sha256_file(output)
    if not sum then
      context.print_error("hecate package: cannot read the archive to checksum it: " .. tostring(message))
      return 1
    end
    local base = output:match("([^/\\]+)$") or output
    dependencies.fs.write(output .. ".sha256", sum .. "  " .. base .. "\n")
    context.emit({ archive = output, sha256 = sum, files = content },
      ("Wrote %s (%s) and %s.sha256"):format(output, sum:sub(1, 12) .. "...", output))
    return 0
  end)
end

--- Runs `hecate package` with the real file system, `tar` and the digest of the CLI.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local reactor = require("hecate.reactor")
  local digest = require("hecate.cli.digest")
  ---@param path string
  ---@return string?
  local function read_file(path)
    if not reactor.fs.stat(path) then return nil end
    return (reactor.fs.read_file(path))
  end
  local windows = package.config:sub(1, 1) == "\\"
  local root = os.getenv("SystemRoot") or "C:\\Windows"
  return command.execute(context, {
    fs = {
      read = read_file,
      exists = function(path) return reactor.fs.stat(path) ~= nil end,
      write = function(path, text) reactor.fs.write_file(path, text) end,
      remove = function(path) reactor.fs.remove(path) end,
    },
    run = function(task) return reactor.run(task) end,
    run_process = function(program, args, options) return reactor.run_process(program, args, options) end,
    sha256_file = digest.sha256_file,
    tar = windows and (root .. "\\System32\\tar.exe") or "tar",
    windows = windows,
  })
end

return command
