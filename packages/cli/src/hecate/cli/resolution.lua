-- From what LuaRocks installed to the records of `hecate.lock` (ADR 0009): reads the rockspec of each installed rock
-- (its source, its dependencies, whether it compiles C code) and assembles a lockfile from the pins of
-- `luarocks.lock`. Pure over text: the caller reads the files and runs LuaRocks.
--
-- What `sha256` covers (`checksum_of`): for a pure-Lua rock, the files it installed (the list is the `rock_manifest` that
-- LuaRocks writes), so that `install --frozen` detects an upstream that changed after locking (a moved tag, a replaced
-- archive); for a native rock, whose files differ per platform, the installed rockspec. LuaRocks keeps no source
-- archive and verifies only an optional `source.md5`, so the first resolution trusts what the server delivers.
global <const> require, load, type, tostring, ipairs, pairs, table, error

local core = require("hecate.core")
local sandbox = require("hecate.cli.internal.sandbox")
local lockfile = require("hecate.cli.lockfile")

---@class hecate.cli.RockspecFacts
---@field source string  `source.url`
---@field dependencies string[]  names of the rocks it depends on, lower case, without `lua`, sorted
---@field native boolean  true when building it compiles C code

---@class hecate.cli.ResolutionInput
---@field manifest hecate.cli.Manifest
---@field pins table<string, string>  rock name to exact version (`luarocks.parse_lock`)
---@field rockspecs table<string, string>  rock name to the text of its installed rockspec
---@field files_digests? table<string, string>  rock name to `installed_files_digest`; a rock without one (or a native rock) is checked by its rockspec
---@field lua string  exact Lua version
---@field luarocks string  exact LuaRocks version
---@field sha256? fun(data: string): string  default: `hecate.cli.digest.sha256`

--- Turning the result of an installation into a lockfile.
---@class hecate.cli.resolution
local M = {}

local function fail(message, context)
  error(core.ConfigurationError({ message = message, context = context }), 0)
end

--- The facts `hecate.lock` needs from the text of a rockspec. The rockspec is Lua that sets globals: it is run in an
--- empty environment under the limits of the manifest. Raises `hecate.core.ConfigurationError` naming `name` when it
--- cannot be read or has no `source.url`.
---@param name string  the rock, for messages
---@param text string
---@return hecate.cli.RockspecFacts facts
function M.read_rockspec(name, text)
  local environment = {}
  local chunk, message = load(text, "=" .. name .. ".rockspec", "t", environment)
  if not chunk then error(core.ConfigurationError({ message = name .. ".rockspec: " .. tostring(message), context = { rock = name } }), 0) end
  local ok, err = sandbox.run(chunk)
  if not ok then fail(name .. ".rockspec: " .. tostring(err), { rock = name }) end
  local source = type(environment.source) == "table" and environment.source.url or nil
  if type(source) ~= "string" or source == "" then
    fail(name .. ".rockspec has no source.url", { rock = name })
  end

  local dependencies, seen = {}, {}
  if type(environment.dependencies) == "table" then
    for _, entry in ipairs(environment.dependencies) do
      local dependency = type(entry) == "string" and entry:match("^%s*([%w%.%-%_/]+)") or nil
      if dependency then
        dependency = dependency:lower()
        if dependency ~= "lua" and not seen[dependency] then
          seen[dependency] = true
          dependencies[#dependencies + 1] = dependency
        end
      end
    end
  end
  table.sort(dependencies)

  -- Native: a build that is not the builtin Lua-only one, or a builtin module with C sources.
  local build = type(environment.build) == "table" and environment.build or {}
  local kind = build.type or "builtin"
  local native = kind ~= "builtin" and kind ~= "none" and kind ~= "module"
  if not native and type(build.modules) == "table" then
    for _, spec in pairs(build.modules) do
      if type(spec) == "table" then
        native = true
      elseif type(spec) == "string" and not spec:match("%.lua$") then
        native = true
      end
    end
  end
  return { source = source, dependencies = dependencies, native = native }
end

--- Assembles and validates the lockfile of an installation. `development` is true for a rock that no runtime
--- dependency of the manifest reaches. A dependency named by a rockspec that is not pinned (a rock LuaRocks provides
--- itself) is left out of the edges. Raises `hecate.core.ConfigurationError` when a pinned rock has no rockspec, one
--- cannot be read, or a direct dependency of the manifest is not pinned.
---@param input hecate.cli.ResolutionInput
---@return hecate.cli.Lockfile lock
function M.build_lockfile(input)
  local sha256 = input.sha256 or require("hecate.cli.digest").sha256
  local by_lower = {}
  for name in pairs(input.pins) do by_lower[name:lower()] = name end

  local facts = {}
  for name in pairs(input.pins) do
    local text = input.rockspecs[name]
    if text == nil then error(core.ConfigurationError({ message = "no installed rockspec for '" .. name .. "'", context = { rock = name } }), 0) end
    facts[name] = M.read_rockspec(name, text)
  end

  local function edges(name)
    local list = {}
    for _, dependency in ipairs(facts[name].dependencies) do
      local target = by_lower[dependency]
      if target then list[#list + 1] = target end
    end
    table.sort(list)
    return list
  end

  local runtime = {}
  local function reach(name)
    if runtime[name] then return end
    runtime[name] = true
    for _, target in ipairs(edges(name)) do reach(target) end
  end
  for name in pairs(input.manifest.dependencies or {}) do
    local pinned = by_lower[name:lower()]
    if not pinned then fail("'" .. name .. "' is a dependency of the manifest but LuaRocks did not pin it", { rock = name }) end
    reach(pinned)
  end
  for name in pairs(input.manifest.development_dependencies or {}) do
    if not by_lower[name:lower()] then
      fail("'" .. name .. "' is a development dependency of the manifest but LuaRocks did not pin it", { rock = name })
    end
  end

  local rocks = {}
  for name, version in pairs(input.pins) do
    local files_digest = (input.files_digests or {})[name]
    local by_files = files_digest ~= nil and not facts[name].native
    rocks[name] = {
      version = version,
      source = facts[name].source,
      sha256 = by_files and files_digest or sha256(input.rockspecs[name] --[[@as string]]),
      checksum_of = by_files and "files" or "rockspec",
      dependencies = edges(name),
      development = not runtime[name],
      native = facts[name].native,
    }
  end
  return lockfile.validate({ format = lockfile.FORMAT, lua = input.lua, luarocks = input.luarocks, rocks = rocks })
end

--- The directories of a rock's `rock_manifest` whose files are deployed into the tree and run: `lua` (modules), `lib`
--- (compiled modules) and `bin` (scripts). Documentation and configuration are not part of the digest.
local DEPLOYED = { "bin", "lib", "lua" }

---@class hecate.cli.FilesDigestInput
---@field manifest_text string  the text of the `rock_manifest` of the rock
---@field read_file fun(category: string, path: string): string?  the bytes of the installed file `path` of a category (`lua`, `lib` or `bin`), nil when it is missing
---@field sha256? fun(data: string): string  default: `hecate.cli.digest.sha256`

local function walk(node, prefix, out)
  for name, value in pairs(node) do
    local path = prefix == "" and name or (prefix .. "/" .. name)
    if type(value) == "table" then walk(value, path, out) else out[#out + 1] = path end
  end
end

--- One SHA-256 for the files a rock installed: for each file of the `lua`, `lib` and `bin` directories of its
--- `rock_manifest`, sorted by category and path, the line `<sha256 of the file>  <category>/<path>`; the digest is
--- that of the concatenated lines. Returns nil when the rock installed no such file (a rock of dependencies only).
--- Raises `hecate.core.ConfigurationError` when the manifest cannot be read or an installed file is missing.
---@param input hecate.cli.FilesDigestInput
---@return string? digest
function M.installed_files_digest(input)
  local sha256 = input.sha256 or require("hecate.cli.digest").sha256
  local environment = {}
  local chunk, message = load(input.manifest_text, "=rock_manifest", "t", environment)
  if not chunk then error(core.ConfigurationError({ message = "rock_manifest: " .. tostring(message) }), 0) end
  local ok, err = sandbox.run(chunk)
  if not ok then fail("rock_manifest: " .. tostring(err), {}) end
  local manifest = environment.rock_manifest
  if type(manifest) ~= "table" then fail("rock_manifest: expected `rock_manifest = { ... }`", {}) end

  local lines = {}
  for _, category in ipairs(DEPLOYED) do
    local node = manifest[category]
    if type(node) == "table" then
      local paths = {}
      walk(node, "", paths)
      for _, path in ipairs(paths) do
        local data = input.read_file(category, path)
        if data == nil then
          error(core.ConfigurationError({
            message = "the installed file " .. category .. "/" .. path .. " listed in rock_manifest is missing",
            context = { category = category, path = path },
          }), 0)
        end
        lines[#lines + 1] = sha256(data) .. "  " .. category .. "/" .. path .. "\n"
      end
    end
  end
  if #lines == 0 then return nil end
  table.sort(lines, function(a, b) return a:sub(67) < b:sub(67) end)
  return sha256(table.concat(lines))
end

--- Checks what is installed against a lockfile, as `install --frozen` does after installing: for each rock the
--- checksum is recomputed the way `checksum_of` says and compared. `current[name]` holds the text of the installed
--- rockspec and, for a pure-Lua rock, the `installed_files_digest`. Returns the problems, sorted: a rock that is
--- missing, or whose content differs from the lock, each with what to do.
---@param lock hecate.cli.Lockfile
---@param current table<string, { rockspec: string, files_digest?: string }>
---@param sha256? fun(data: string): string
---@return string[] problems
function M.verify(lock, current, sha256)
  sha256 = sha256 or require("hecate.cli.digest").sha256
  local problems = {}
  for name, rock in pairs(lock.rocks) do
    local installed = current[name]
    if installed == nil then
      problems[#problems + 1] = "'" .. name .. "' is in the lockfile but not installed: run `hecate install`"
    else
      local actual
      if rock.checksum_of == "files" then
        actual = installed.files_digest
      else
        actual = sha256(installed.rockspec)
      end
      if actual ~= rock.sha256 then
        problems[#problems + 1] = "'" .. name .. "' " .. rock.version .. " does not match hecate.lock ("
          .. (rock.checksum_of == "files" and "its installed files differ" or "its rockspec differs")
          .. "): the source changed after it was locked, or the tree is out of date. Run `hecate install` to reinstall, or `hecate update "
          .. name .. "` if the change is expected"
      end
    end
  end
  table.sort(problems)
  return problems
end

return M
