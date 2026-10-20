-- The reference of a monorepo checkout: runs LuaLS on the `src` of each package, generates
-- the pages (reference.lua) and writes them below `<locale directory>/reference/<package>/`.
-- Generated pages are never edited by hand: a package directory is rewritten whole, and only if
-- every file in it carries the generated marker (otherwise it is left alone and reported).
-- Examples are the tested files `packages/<package>/examples/<symbol>.lua` (coding-standards.md).
global <const> require, ipairs, table, error, type, string, tostring

local core = require("hecate.core")
local reference = require("hecate.doc.reference")
local luals = require("hecate.doc.luals")

local M = {}

--- The packages whose public modules follow the annotation convention (coding-standards.md),
--- in sidebar order. Add a package here once its modules are annotated.
M.DEFAULT_PACKAGES = { "core", "reactor", "net", "json" }

---@class hecate.doc.ReferenceSiteOptions
---@field root string  repository root (holds `packages/`)
---@field packages? string[]  package names, in sidebar order (default `DEFAULT_PACKAGES`)
---@field out string  locale directory of the site, for example `website/en`
---@field fs hecate.doc.FileSystem
---@field executable? string  `lua-language-server` (default: found on the path)
---@field config? string  `.luarc.json` (default `<root>/.luarc.json`)
---@field since? string

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
    if entry.is_directory then
      if not generated_only(fs, path) then return false end
    elseif entry.name:find("%.md$") then
      if not reference.is_generated(fs:read(path) or "") then return false end
    else
      return false
    end
  end
  return true
end

--- Writes the pages of a result below `out`, replacing the previous pages of each package.
---@param fs hecate.doc.FileSystem
---@param out string  locale directory
---@param result hecate.doc.ReferenceResult
---@param packages string[]
---@return string[] problems
function M.write(fs, out, result, packages)
  local problems = {}
  local writable = {}
  for _, name in ipairs(packages) do
    local directory = ("%s/reference/%s"):format(out, name)
    if generated_only(fs, directory) then
      if fs:exists(directory) then fs:remove_tree(directory) end
      writable[name] = true
    else
      problems[#problems + 1] = ("%s holds files that are not generated; left alone"):format(directory)
    end
  end
  for _, path in ipairs(result.order) do
    local name = path:match("^reference/([^/]+)/")
    if name and writable[name] then fs:write(out .. "/" .. path, result.pages[path]) end
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
  if type(options) ~= "table" or not options.root or not options.out or not options.fs then
    error(core.ArgumentError("reference_site.run expects { root, out, fs }"), 2)
  end
  local fs = options.fs
  local report = { pages = 0, packages = {}, problems = {} }
  local executable = options.executable or luals.locate()
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
    local source = ("%s/packages/%s/src"):format(options.root, name)
    if fs:exists(source) then
      inputs[#inputs + 1] = {
        name = name,
        export = luals.export(executable, source, { config = options.config or (options.root .. "/.luarc.json"), fs = fs }),
      }
      names[#names + 1] = name
    else
      report.problems[#report.problems + 1] = ("package %s has no src directory at %s"):format(name, source)
    end
  end
  local result = reference.generate(inputs, {
    since = options.since,
    examples = function(symbol)
      local package_name = symbol:match("^hecate%.([^.]+)")
      local path = ("packages/%s/examples/%s.lua"):format(package_name or "", symbol)
      local source = fs:read(options.root .. "/" .. path)
      return source, path
    end,
  })
  for _, problem in ipairs(result.problems) do report.problems[#report.problems + 1] = problem end
  for _, problem in ipairs(M.write(fs, options.out, result, names)) do report.problems[#report.problems + 1] = problem end
  report.pages = #result.order
  report.packages = names
  return report
end

return M
