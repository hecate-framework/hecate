-- The build entry point: content tree in, static site out.
global <const> require, type, error, ipairs, pcall, table, load, tostring

local core = require("hecate.core")
local errors = require("hecate.doc.errors")
local Site = require("hecate.doc.site")

local M = {}

---@class hecate.doc.BuildOptions : hecate.doc.SiteOptions
---@field out string  output directory
---@field clean? boolean  empty the output directory first (only if a previous build wrote it)
---@field strict? boolean  raise `hecate.doc.BuildError` when `problems` is not empty

---@class hecate.doc.BuildReport
---@field files integer  files written, the marker file included
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer }>
---@field problems string[]  broken links, missing titles and similar, sorted and unique

--- Loads a site configuration file. The file is Lua that returns a table; it runs with an
--- empty environment, so it can only describe data (it cannot read files or call anything).
---@param path string
---@param fs hecate.doc.FileSystem
---@return hecate.doc.SiteConfig
function M.load_config(path, fs)
  local text = fs:read(path)
  if text == nil then
    error(errors.BuildError({ message = "doc.build: cannot read site configuration " .. path, context = { path = path } }), 0)
  end
  local chunk, message = load(text, "=" .. path, "t", {})
  if not chunk then
    error(core.ConfigurationError({ message = "doc.build: invalid site configuration: " .. tostring(message), context = { path = path } }), 0)
  end
  local ok, config = pcall(chunk)
  if not ok or type(config) ~= "table" then
    error(core.ConfigurationError({
      message = "doc.build: the site configuration must return a table" .. (ok and "" or (": " .. tostring(config))),
      context = { path = path },
    }), 0)
  end
  return config
end

local function clean_output(fs, out)
  if not fs:exists(out) then return end
  if fs:read(out .. "/" .. Site.MARKER) == nil and #(fs:list(out) or {}) > 0 then
    error(errors.BuildError({
      message = ("doc.build: refusing to clean %s: it was not written by hecate.doc (no %s file)"):format(out, Site.MARKER),
      context = { path = out },
    }), 0)
  end
  fs:remove_tree(out)
end

--- Builds a site: reads `<source>/<locale>/**/*.md`, renders every page for every locale
--- with the theme, writes the search indexes, the theme files and the other static files
--- to `options.out`, and returns a report. The output is deterministic.
---@param options hecate.doc.BuildOptions
---@return hecate.doc.BuildReport
function M.build(options)
  if type(options) ~= "table" or type(options.out) ~= "string" or options.out == "" then
    error(core.ArgumentError("doc.build: expects options with an `out` directory"), 2)
  end
  local out = options.out:gsub("/+$", "")
  local site = Site(options):load()
  if options.clean then clean_output(options.fs, out) end
  local bytes = 0
  local files = site:emit(function(path, data)
    bytes = bytes + #data
    options.fs:write(out .. "/" .. path, data)
  end)
  local report = { files = files, bytes = bytes, locales = {}, problems = {} }
  local seen = {}
  for _, problem in ipairs(site.problems) do
    if not seen[problem] then
      seen[problem] = true
      report.problems[#report.problems + 1] = problem
    end
  end
  table.sort(report.problems)
  for _, locale in ipairs(site.config.locales) do
    local entry = { pages = 0, fallbacks = 0 }
    for _, page in ipairs(site:pages(locale.code)) do
      entry.pages = entry.pages + 1
      if page.fallback then entry.fallbacks = entry.fallbacks + 1 end
    end
    report.locales[locale.code] = entry
  end
  if options.strict and #report.problems > 0 then
    error(errors.BuildError({
      message = ("doc.build: %d problem(s):\n  %s"):format(#report.problems, table.concat(report.problems, "\n  ")),
      context = { problems = report.problems },
    }), 0)
  end
  return report
end

return M
