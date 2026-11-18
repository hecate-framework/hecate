-- The build entry point: content tree in, static site out.
global <const> require, type, error, ipairs, pairs, pcall, table, load, tostring

local core = require("hecate.core")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local html = require("hecate.doc.internal.html")
local Site = require("hecate.doc.site")

--- The build entry point: loads the site configuration and builds the static site.
---@class hecate.doc.build
local M = {}

---@class hecate.doc.BuildOptions : hecate.doc.SiteOptions
---@field out string  output directory
---@field clean? boolean  empty the output directory first (only if a previous build wrote it)
---@field strict? boolean  raise `hecate.doc.BuildError` when `problems` is not empty

---@class hecate.doc.BuildReport
---@field files integer  files written, the marker file included
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer, unpublished: integer }>  `unpublished`: pages left out because their audience is not published
---@field problems string[]  broken links, missing titles and similar, sorted and unique (those of every site)
---@field sites hecate.doc.SiteReport[]  one entry per site written, in the order of `audiences`: one site, or one per audience when several audiences are published as separate sites (`audience_sites`, OQ-144)

---@class hecate.doc.SiteReport
---@field audiences hecate.doc.Audience[]  audiences the site publishes (one for a separate site)
---@field directory string  directory of the site below `out` ("" when the site is written at the root, `maintainer` for a separate site)
---@field files integer  files written to the site
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer, unpublished: integer }>  `unpublished`: pages left out of this site, those of another audience included
---@field problems string[]  problems of this site, sorted and unique: a link to a page of another audience is one of them

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
  if fs.is_link and fs:is_link(out) then
    error(errors.BuildError({
      message = ("doc.build: refusing to clean %s: it is a symbolic link; give the real output directory"):format(out),
      context = { path = out },
    }), 0)
  end
  if not fs:exists(out) then return end
  if fs:read(out .. "/" .. Site.MARKER) == nil and #(fs:list(out) or {}) > 0 then
    error(errors.BuildError({
      message = ("doc.build: refusing to clean %s: it was not written by hecate.doc (no %s file)"):format(out, Site.MARKER),
      context = { path = out },
    }), 0)
  end
  fs:remove_tree(out)
end

local function sorted_unique(list)
  local seen, out = {}, {}
  for _, problem in ipairs(list) do
    if not seen[problem] then
      seen[problem] = true
      out[#out + 1] = problem
    end
  end
  table.sort(out)
  return out
end

local function locale_entry(site, code)
  local entry = { pages = 0, fallbacks = 0, unpublished = #site:unpublished(code) }
  for _, page in ipairs(site:pages(code)) do
    entry.pages = entry.pages + 1
    if page.fallback then entry.fallbacks = entry.fallbacks + 1 end
  end
  return entry
end

-- The page at the root of the output when several sites are written: it leads to the first audience.
local function root_redirect(config, directory)
  local target = config.base .. directory .. "/" .. config.default_locale .. "/"
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n"
    .. "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n<link rel=\"canonical\" href=\"%s\">\n</head>\n"
    .. "<body>\n<p><a href=\"%s\">%s</a></p>\n</body>\n</html>\n"):format(
    html.escape(config.default_locale), html.escape(config.title), html.escape(target),
    html.escape(config.url and (config.url .. target) or target), html.escape(target), html.escape(config.title))
end

--- Builds a site: reads `<source>/<locale>/**/*.md`, renders every page for every locale
--- with the theme, writes the search indexes, the theme files and the other static files
--- to `options.out`, and returns a report. The output is deterministic.
---
--- With several audiences published and `audience_sites = "separate"` (the default), one complete site is
--- written per audience below `<out>/<audience>/` (own pages, navigation, search index, sitemap, `llms.txt`,
--- theme files and 404), none holding a page of another audience; `<out>/` itself holds only the marker file and
--- a redirect to the first audience. A link from a page to a page of another audience is a problem of the site
--- of the page, like a broken link. With one audience, or with `audience_sites = "merged"`, one site is written
--- at `<out>/` (OQ-144).
---@param options hecate.doc.BuildOptions
---@return hecate.doc.BuildReport
function M.build(options)
  if type(options) ~= "table" or type(options.out) ~= "string" or options.out == "" then
    error(core.ArgumentError("doc.build: expects options with an `out` directory"), 2)
  end
  local out = options.out:gsub("/+$", "")
  local config = config_module.normalise(options.config)
  local separate = config.audience_sites == "separate" and #config.audiences > 1
  local specs = {}
  if separate then
    for _, audience in ipairs(config.audiences) do
      local own = {}
      for key, value in pairs(options) do own[key] = value end
      local sub = {}
      for key, value in pairs(config) do sub[key] = value end
      sub.audiences = { audience }
      sub.base = config.base .. audience .. "/"
      own.config = sub
      specs[#specs + 1] = { audiences = { audience }, directory = audience, options = own }
    end
  else
    specs[1] = { audiences = config.audiences, directory = "", options = options }
  end
  -- Every site is loaded before anything is written: a failing build leaves no partial output.
  for _, spec in ipairs(specs) do spec.site = Site(spec.options):load() end
  if options.clean then clean_output(options.fs, out) end
  local bytes, files = 0, 0
  local function write(path, data)
    bytes = bytes + #data
    files = files + 1
    options.fs:write(out .. "/" .. path, data)
  end
  if separate then
    write(Site.MARKER, "Written by hecate.doc. This directory is emptied by builds that ask for a clean output.\n")
    write("index.html", root_redirect(config, specs[1].directory))
  end
  local report = { files = 0, bytes = 0, locales = {}, problems = {}, sites = {} }
  local all_problems = {}
  for _, spec in ipairs(specs) do
    local prefix = spec.directory == "" and "" or (spec.directory .. "/")
    local site_bytes = 0
    local site_files = spec.site:emit(function(path, data)
      site_bytes = site_bytes + #data
      write(prefix .. path, data)
    end)
    local entry = { audiences = spec.audiences, directory = spec.directory, files = site_files, bytes = site_bytes,
      locales = {}, problems = sorted_unique(spec.site.problems) }
    for _, locale in ipairs(config.locales) do entry.locales[locale.code] = locale_entry(spec.site, locale.code) end
    report.sites[#report.sites + 1] = entry
    for _, problem in ipairs(entry.problems) do all_problems[#all_problems + 1] = problem end
  end
  report.files, report.bytes, report.problems = files, bytes, sorted_unique(all_problems)
  for _, locale in ipairs(config.locales) do
    local total = { pages = 0, fallbacks = 0, unpublished = 0 }
    local hidden = {}
    for index, spec in ipairs(specs) do
      local entry = report.sites[index].locales[locale.code]
      total.pages = total.pages + entry.pages
      total.fallbacks = total.fallbacks + entry.fallbacks
      for _, page in ipairs(spec.site:unpublished(locale.code)) do hidden[page.id] = (hidden[page.id] or 0) + 1 end
    end
    -- Unpublished: left out of every site (a page of another audience is in that audience's site).
    for _, count in pairs(hidden) do
      if count == #specs then total.unpublished = total.unpublished + 1 end
    end
    report.locales[locale.code] = total
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
