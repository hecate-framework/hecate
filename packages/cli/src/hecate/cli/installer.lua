-- The installation of a project's dependencies (ADR 0009, cli-and-packaging.md): joins the manifest, LuaRocks, the
-- lockfile and the checksums. The file system and LuaRocks are injected, so the sequence is testable without either;
-- the `install` command supplies the real ones.
global <const> require, ipairs, pairs, table, error

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local lockfile = require("hecate.cli.lockfile")
local luarocks = require("hecate.cli.luarocks")
local resolution = require("hecate.cli.resolution")

---@class hecate.cli.InstallFileSystem
---@field read fun(path: string): string?  the text of a file, nil when it does not exist
---@field write fun(path: string, text: string)  writes a file, creating its directories

---@class hecate.cli.InstallOptions
---@field manifest_text string  the text of `hecate.project.lua`
---@field lock_text? string  the text of `hecate.lock`, when it exists
---@field frozen? boolean  install exactly what the lockfile says, and verify it
---@field fs hecate.cli.InstallFileSystem
---@field luarocks hecate.cli.LuaRocks
---@field work_dir string  where the generated rockspec and `luarocks.lock` live (`.hecate/luarocks`)
---@field tree string  the project-local tree
---@field lua string  exact Lua version (the first two numbers name the directories of the tree)
---@field luarocks_version string  exact LuaRocks version
---@field rock_directory? fun(name: string, version: string): string  where LuaRocks keeps a rock's rockspec and `rock_manifest`
---@field deployed_directory? fun(category: string): string  the directory of the `lua`, `lib` or `bin` files in the tree
---@field sha256? fun(data: string): string
---@field lua_headers? { directory: string, files: table<string, string> }  the headers of the embedded Lua (`lua.h`, ...): written to `directory`, which becomes `LUA_INCDIR`, so that a rock with C code builds without a system Lua
---@field refresh? string[]  rocks removed from the tree before installing, so that LuaRocks takes the newest version the constraints allow (`update`); `{}` stands for every rock of the tree; ignored with `frozen`

---@class hecate.cli.InstallResult
---@field lock hecate.cli.Lockfile
---@field lock_text string  the text written to `hecate.lock` (unchanged under `--frozen`)
---@field installed integer  number of rocks in the tree

--- The installation sequence.
---@class hecate.cli.installer
local M = {}

local function fail(message, context)
  error(core.ConfigurationError({ message = message, context = context or {} }), 0)
end

local function join(directory, name)
  return (directory:gsub("[/\\]+$", "")) .. "/" .. name
end

local function names_of(manifest)
  local names, seen = {}, {}
  for _, set in ipairs({ manifest.dependencies or {}, manifest.development_dependencies or {} }) do
    for name in pairs(set) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
  end
  table.sort(names)
  return names
end

--- What each pinned rock installed: its rockspec text, and for a pure-Lua rock the digest of its files.
local function read_installed(options, pins)
  local line = options.lua:match("^%d+%.%d+") or options.lua
  local rock_directory = options.rock_directory or function(name, version)
    return join(options.tree, "lib/luarocks/rocks-" .. line .. "/" .. name .. "/" .. version)
  end
  local deployed = options.deployed_directory or function(category)
    if category == "lua" then return join(options.tree, "share/lua/" .. line) end
    if category == "lib" then return join(options.tree, "lib/lua/" .. line) end
    return join(options.tree, "bin")
  end
  local rockspecs, digests = {}, {}
  for name, version in pairs(pins) do
    local directory = rock_directory(name, version)
    local text = options.fs.read(join(directory, name .. "-" .. version .. ".rockspec"))
    if text == nil then fail("no installed rockspec for '" .. name .. "' " .. version .. " under " .. directory, { rock = name }) end
    rockspecs[name] = text
    local manifest_text = options.fs.read(join(directory, "rock_manifest"))
    if manifest_text ~= nil then
      digests[name] = resolution.installed_files_digest({
        manifest_text = manifest_text,
        sha256 = options.sha256,
        read_file = function(category, path) return options.fs.read(join(deployed(category), path)) end,
      })
    end
  end
  return rockspecs, digests
end

--- Installs the dependencies of the manifest into the tree and writes (or, with `frozen`, verifies) `hecate.lock`.
--- Without `frozen`: writes the LuaRocks configuration and the generated rockspec, installs, pins, reads what was
--- installed and returns the new lockfile text; the caller writes `hecate.lock`. With `frozen`: stops before any
--- installation when the lockfile is missing or out of date, and fails afterwards when the installed content differs
--- from the lock. Suspends (it runs LuaRocks).
---@async
---@param options hecate.cli.InstallOptions
---@return hecate.cli.InstallResult result
function M.install(options)
  local manifest = manifest_module.parse(options.manifest_text)
  local existing
  if options.frozen then
    if not options.lock_text then fail("hecate.lock does not exist: run `hecate install` first, then commit it") end
    existing = lockfile.parse(options.lock_text)
    local problems = lockfile.outdated(existing, manifest)
    if #problems > 0 then fail("hecate.lock is out of date with hecate.project.lua:\n  " .. table.concat(problems, "\n  "), { problems = problems }) end
  end

  local rocks = options.luarocks
  local config_path = rocks:environment()
  -- The servers of the manifest are extra ones (cli-and-packaging.md): they come before luarocks.org, which stays.
  if manifest.rocks_servers and #manifest.rocks_servers > 0 then
    local servers = {}
    for _, server in ipairs(manifest.rocks_servers) do servers[#servers + 1] = server end
    servers[#servers + 1] = "https://luarocks.org"
    rocks.options.rocks_servers = servers
  end
  if options.lua_headers then
    local names = {}
    for name in pairs(options.lua_headers.files) do names[#names + 1] = name end
    table.sort(names)
    -- Written only when different: a rock being built may be reading them, and an unchanged file keeps its timestamp.
    for _, name in ipairs(names) do
      local path = join(options.lua_headers.directory, name)
      if options.fs.read(path) ~= options.lua_headers.files[name] then options.fs.write(path, options.lua_headers.files[name]) end
    end
    local variables = {}
    for key, value in pairs(rocks.options.variables or {}) do variables[key] = value end
    variables.LUA_INCDIR = options.lua_headers.directory
    rocks.options.variables = variables
  end
  options.fs.write(config_path, rocks:config_text())
  local rockspec_path = join(options.work_dir, luarocks.rockspec_file_name(manifest))
  local exact
  if existing then
    -- Frozen (cli-and-packaging.md, "install --frozen"): ask LuaRocks for the exact locked versions, so that a newer
    -- release is never fetched and built before the check below.
    exact = {}
    for name, rock in pairs(existing.rocks) do exact[name] = rock.version end
  end
  options.fs.write(rockspec_path, luarocks.rockspec_text(manifest, exact))

  if options.refresh and not options.frozen then
    local targets = options.refresh --[[@as string[] ]]
    if #targets == 0 then
      targets = {}
      for _, rock in ipairs(rocks:installed()) do targets[#targets + 1] = rock.name end
    end
    rocks:remove(targets)
  end

  local installed = rocks:install_dependencies(rockspec_path, names_of(manifest))
  rocks:pin(rockspec_path, options.work_dir)
  local lock_source = options.fs.read(join(options.work_dir, "luarocks.lock"))
  if lock_source == nil then fail("luarocks wrote no luarocks.lock in " .. options.work_dir) end
  local pins = luarocks.parse_lock(lock_source --[[@as string]])
  local rockspecs, digests = read_installed(options, pins)

  if existing then
    local current = {}
    for name in pairs(pins) do current[name] = { rockspec = rockspecs[name], files_digest = digests[name] } end
    local problems = resolution.verify(existing, current, options.sha256)
    if #problems > 0 then fail("the installed rocks do not match hecate.lock:\n  " .. table.concat(problems, "\n  "), { problems = problems }) end
    return { lock = existing, lock_text = options.lock_text --[[@as string]], installed = #installed }
  end

  local lock = resolution.build_lockfile({
    manifest = manifest,
    pins = pins,
    rockspecs = rockspecs,
    files_digests = digests,
    lua = options.lua,
    luarocks = options.luarocks_version,
    sha256 = options.sha256,
  })
  return { lock = lock, lock_text = lockfile.serialize(lock), installed = #installed }
end

return M
