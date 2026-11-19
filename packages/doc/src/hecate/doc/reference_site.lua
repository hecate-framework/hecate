-- The reference of a monorepo checkout: runs LuaLS on the `src` of each package, generates
-- the pages (reference.lua) and writes them below `<locale_dir>/reference/<package>/`.
-- Generated pages are never edited by hand: a package directory is rewritten whole, and only if
-- every file in it carries the generated marker (otherwise it is left alone and reported).
-- Examples are the tested files `packages/<package>/examples/<symbol>.lua` (coding-standards.md).
global <const> require, ipairs, table, error, type, string, tostring

local core = require("hecate.core")
local reference = require("hecate.doc.reference")
local luals = require("hecate.doc.luals")
local options_module = require("hecate.doc.internal.options")

--- Pages of the code reference for the site builder.
---@class hecate.doc.reference_site
local M = {}

--- The packages whose public modules follow the annotation convention (coding-standards.md),
--- in sidebar order. Add a package here once its modules are annotated.
M.DEFAULT_PACKAGES = { "core", "reactor", "net", "json", "log", "http", "router", "schema", "openapi", "container", "config", "kernel", "test" }

---@class hecate.doc.ReferenceSiteOptions
---@field project_dir string  repository root (holds `packages/`) or project directory; must be trusted: LuaLS runs any plugin that a LuaLS configuration reachable from it declares (`.luarc.json`, `.luarc.jsonc`, `.vscode/settings.json`), with full file and command access (see `hecate.doc.luals.export`)
---@field packages? string[]  package names, in sidebar order (default `DEFAULT_PACKAGES`)
---@field locale_dir string  locale directory of the guides that the pages are written into, for example `website/en` (not the directory of the built site)
---@field file_system hecate.doc.FileSystem
---@field language_server_path? string  `lua-language-server` (default: found on the path)
---@field language_server_config_path? string  `.luarc.json`, passed to LuaLS as `--configpath` (default: none is passed; the repository runners `bin/build.lua` and `bin/reference.lua` give `<root>/.luarc.json`)
---@field since? string
---@field internal? boolean  also generate the `maintainer` pages of `*.internal` modules and of non-public classes (default false)
---@field label_audiences? boolean|hecate.doc.Audience  write the `audience` front matter key on every page: `true` by class, an audience for all pages (default false)
---@field separate_audience_sites? boolean  the audiences are built into separate sites and `label_audiences` is `true`: a page links only to pages of its own audience (default false)
---@field sources_dir_pattern? string  `string.format` pattern of a package's source directory below `project_dir` (default `packages/%s/src`; a project uses `src`, with one name)

---@class hecate.doc.ReferenceSiteReport
---@field pages integer
---@field packages string[]
---@field problems string[]
---@field skipped? string  why nothing was generated (LuaLS missing)

local function generated_only(fs, directory)
  local entries = fs:list(directory)
  if entries == nil then return true end
  for _, entry in ipairs(entries) do
    local path = directory .. "/" .. entry.name
    if entry.is_link then
      return false -- a link is never ours: it is not followed, and the directory is left alone
    elseif entry.is_directory then
      if not generated_only(fs, path) then return false end
    elseif entry.name:find("%.md$") then
      if not reference.is_generated(fs:read(path) or "") then return false end
    else
      return false
    end
  end
  return true
end

--- Writes the pages of a result below `locale_dir`, replacing the previous pages of each package.
---@param file_system hecate.doc.FileSystem
---@param locale_dir string  locale directory
---@param result hecate.doc.ReferenceResult
---@param packages string[]
---@return string[] problems
function M.write(file_system, locale_dir, result, packages)
  local fs = file_system
  local problems = {}
  local writable = {}
  for _, name in ipairs(packages) do
    local directory = ("%s/reference/%s"):format(locale_dir, name)
    if generated_only(fs, directory) then
      if fs:exists(directory) then fs:remove_tree(directory) end
      writable[name] = true
    else
      problems[#problems + 1] = ("%s holds files that are not generated; left alone"):format(directory)
    end
  end
  for _, path in ipairs(result.order) do
    local name = path:match("^reference/([^/]+)/")
    if name and writable[name] then fs:write(locale_dir .. "/" .. path, result.pages[path]) end
  end
  return problems
end

--- Generates the reference of the packages and writes it. Does nothing, with `skipped` set,
--- when `lua-language-server` is not installed.
---
--- Raises `hecate.doc.BuildError` if LuaLS fails on a package.
---@param options hecate.doc.ReferenceSiteOptions
---@return hecate.doc.ReferenceSiteReport
function M.run(options)
  if type(options) ~= "table" or not options.project_dir or not options.locale_dir or not options.file_system then
    error(core.ArgumentError("doc.reference_site.run: expects { project_dir, locale_dir, file_system }"), 2)
  end
  options_module.check("doc.reference_site.run", "reference_site", options, options_module.REFERENCE_SITE, 3)
  local fs = options.file_system
  local report = { pages = 0, packages = {}, problems = {} }
  local executable = options.language_server_path or luals.locate()
  if not executable then
    report.skipped = "lua-language-server is not on the path; the reference was not generated"
    return report
  end
  local version = luals.version(executable)
  if version ~= luals.PINNED then
    report.problems[#report.problems + 1] = ("lua-language-server %s, the export format is pinned to %s"):format(
      version or "of unknown version", luals.PINNED)
  end
  local inputs, names = {}, {}
  for _, name in ipairs(options.packages or M.DEFAULT_PACKAGES) do
    local source = options.project_dir .. "/" .. (options.sources_dir_pattern or "packages/%s/src"):format(name)
    if fs:exists(source) then
      inputs[#inputs + 1] = {
        name = name,
        export = luals.export(executable, source, {
          -- None is passed when the option is unset (OQ-142): LuaLS then reads the configuration of the directory it documents.
          language_server_config_path = options.language_server_config_path,
          file_system = fs,
        }),
      }
      names[#names + 1] = name
    else
      report.problems[#report.problems + 1] = ("package %s has no src directory at %s"):format(name, source)
    end
  end
  local result = reference.generate(inputs, {
    since = options.since,
    internal = options.internal,
    label_audiences = options.label_audiences,
    separate_audience_sites = options.separate_audience_sites,
    examples = function(symbol)
      local package_name = symbol:match("^hecate%.([^.]+)")
      local path = ("packages/%s/examples/%s.lua"):format(package_name or "", symbol)
      local source = fs:read(options.project_dir .. "/" .. path)
      return source, path
    end,
  })
  for _, problem in ipairs(result.problems) do report.problems[#report.problems + 1] = problem end
  for _, problem in ipairs(M.write(fs, options.locale_dir, result, names)) do report.problems[#report.problems + 1] = problem end
  report.pages = #result.order
  report.packages = names
  return report
end

return M
