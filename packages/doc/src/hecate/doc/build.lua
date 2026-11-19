-- The build entry point: content tree in, static site out.
global <const> require, type, error, ipairs, pairs, table, load, tostring

local core = require("hecate.core")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local html = require("hecate.doc.internal.html")
local options_module = require("hecate.doc.internal.options")
local paths = require("hecate.doc.internal.paths")
local safe_write = require("hecate.doc.internal.safe_write")
local sandbox = require("hecate.doc.internal.sandbox")
local Site = require("hecate.doc.site")

--- The build entry point: loads the site configuration and builds the static site.
---@class hecate.doc.build
local M = {}

---@class hecate.doc.BuildOptions : hecate.doc.SiteOptions
---@field output_dir string  directory the static site is written to
---@field clean_output_dir? boolean  empty `output_dir` first (only if a previous build wrote it)
---@field fail_on_problems? boolean  raise `hecate.doc.BuildError` when `problems` is not empty

---@class hecate.doc.BuildReport
---@field files integer  files written, the marker file included
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer, unpublished: integer }>  `unpublished`: pages left out because their audience is not published
---@field problems string[]  broken links, missing titles and similar, sorted and unique (those of every site)
---@field sites hecate.doc.SiteReport[]  one entry per site written, in the order of `audiences`: one site, or one per audience when several audiences are published as separate sites (`audience_sites`, OQ-144)

---@class hecate.doc.SiteReport
---@field audiences hecate.doc.Audience[]  audiences the site publishes (one for a separate site)
---@field directory string  directory of the site below `output_dir` ("" when the site is written at the root, `maintainer` for a separate site)
---@field files integer  files written to the site
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer, unpublished: integer }>  `unpublished`: pages left out of this site, those of another audience included
---@field problems string[]  problems of this site, sorted and unique: a link to a page of another audience is one of them

--- Loads a site configuration file. The file is Lua that returns a table; it runs with an empty environment (no global
--- function: it cannot read files, load code or start a process) in a coroutine with a limit of instructions and of
--- memory growth (`hecate.doc.internal.sandbox`), so that a loop or a runaway allocation in Lua code ends with an error.
--- It is the code of the project, not a sandbox against a hostile file: the methods of strings stay reachable from any
--- string (`("x"):rep(1e10)`) and no hook can interrupt one call into C.
---@param file_system hecate.doc.FileSystem
---@param path string
---@return hecate.doc.SiteConfiguration
function M.load_site_configuration(file_system, path)
  local text = file_system:read(path)
  if text == nil then
    error(errors.BuildError({
      message = "doc.build: cannot read site configuration " .. path .. " (no such file, or it is a directory)",
      context = { path = path },
    }), 0)
  end
  local chunk, message = load(text, "=" .. path, "t", {})
  if not chunk then
    error(core.ConfigurationError({ message = "doc.build: invalid site configuration: " .. tostring(message), context = { path = path } }), 0)
  end
  local ok, site_configuration = sandbox.run(chunk)
  if not ok or type(site_configuration) ~= "table" then
    error(core.ConfigurationError({
      message = "doc.build: the site configuration must return a table" .. (ok and "" or (": " .. tostring(site_configuration))),
      context = { path = path },
    }), 0)
  end
  return site_configuration
end

local function clean_output(fs, output_dir)
  if fs.is_link and fs:is_link(output_dir) then
    error(errors.BuildError({
      message = ("doc.build: refusing to clean %s: it is a symbolic link; give the real output directory"):format(output_dir),
      context = { path = output_dir },
    }), 0)
  end
  if not fs:exists(output_dir) then return end
  if fs:read(output_dir .. "/" .. Site.MARKER) == nil and #(fs:list(output_dir) or {}) > 0 then
    error(errors.BuildError({
      message = ("doc.build: refusing to clean %s: it was not written by hecate.doc (no %s file)"):format(output_dir, Site.MARKER),
      context = { path = output_dir },
    }), 0)
  end
  fs:remove_tree(output_dir)
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
  local target = config.base_path .. directory .. "/" .. config.default_locale .. "/"
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n"
    .. "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n<link rel=\"canonical\" href=\"%s\">\n</head>\n"
    .. "<body>\n<p><a href=\"%s\">%s</a></p>\n</body>\n</html>\n"):format(
    html.escape(config.default_locale), html.escape(config.title), html.escape(target),
    html.escape(config.site_origin and (config.site_origin .. target) or target), html.escape(target), html.escape(config.title))
end

--- Builds a site: reads `<guides_dir>/<locale>/**/*.md`, renders every page for every locale
--- with the theme, writes the search indexes, the theme files and the other static files
--- to `options.output_dir`, and returns a report. The output is deterministic.
---
--- With several audiences published and `audience_sites = "separate"` (the default), one complete site is
--- written per audience below `<output_dir>/<audience>/` (own pages, navigation, search index, sitemap, `llms.txt`,
--- theme files and 404), none holding a page of another audience; `<output_dir>/` itself holds only the marker file and
--- a redirect to the first audience. A link from a page to a page of another audience is a problem of the site
--- of the page, like a broken link. With one audience, or with `audience_sites = "merged"`, one site is written
--- at `<output_dir>/` (OQ-144).
---@param options hecate.doc.BuildOptions
---@return hecate.doc.BuildReport
function M.build(options)
  if type(options) ~= "table" or type(options.output_dir) ~= "string" or options.output_dir == "" then
    error(core.ArgumentError("doc.build: expects options with an `output_dir` directory"), 2)
  end
  options_module.check("doc.build", "build", options, options_module.BUILD, 3)
  local field, expected = options_module.invalid(options, { "guides_dir", "output_dir", "file_system", "theme_file_system",
    "theme_files_dir", "last_updated", "site_configuration", "clean_output_dir", "fail_on_problems" })
  if field then options_module.refuse("doc.build", field, expected or "valid", 3) end
  -- `\` is a separator at this entry point; below it everything works with `/`.
  local output_dir = paths.separators(options.output_dir):gsub("/+$", "")
  if output_dir == "" or paths.is_root(output_dir) or paths.is_root(output_dir .. "/") then
    options_module.refuse("doc.build", "output_dir", "a directory, not the root of a file system", 3)
  end
  local guides_dir = paths.separators(options.guides_dir or "")
  -- The output is rewritten, and emptied with `clean_output_dir`: it may lie below the guides (the default layout of a
  -- project is `docs/dist` below `docs`), but it is never the guides themselves or a directory that holds them.
  local relation = paths.relation(guides_dir, output_dir)
  if relation == "same" or relation == "inside" then
    options_module.refuse("doc.build", "output_dir", ("a directory that is not `guides_dir` and does not hold it (`output_dir` %s, `guides_dir` %s)")
      :format(options.output_dir, options.guides_dir), 3)
  end
  local config = config_module.normalise(options.site_configuration)
  local separate = config.audience_sites == "separate" and #config.audiences > 1
  -- What `Site` is given: its own options, not those of the output.
  local function site_options(site_configuration, others)
    local own = { site_configuration = site_configuration, other_site_audiences = others }
    for _, key in ipairs(options_module.SITE) do
      if key ~= "site_configuration" and key ~= "other_site_audiences" then own[key] = options[key] end
    end
    return own
  end
  local specs = {}
  if separate then
    for _, audience in ipairs(config.audiences) do
      local sub = {}
      for key, value in pairs(config) do sub[key] = value end
      sub.audiences = { audience }
      sub.base_path = config.base_path .. audience .. "/"
      local others = {}
      for _, other in ipairs(config.audiences) do
        if other ~= audience then others[#others + 1] = other end
      end
      specs[#specs + 1] = { audiences = { audience }, directory = audience, options = site_options(sub, others) }
    end
  else
    specs[1] = { audiences = config.audiences, directory = "", options = site_options(options.site_configuration) }
  end
  -- Every site is loaded before anything is written: a failing build leaves no partial output.
  for _, spec in ipairs(specs) do spec.site = Site(spec.options):load() end
  if options.clean_output_dir then clean_output(options.file_system, output_dir) end
  local bytes, files = 0, 0
  local guard = safe_write.guard(options.file_system, output_dir)
  local function write(path, data)
    bytes = bytes + #data
    files = files + 1
    guard(output_dir .. "/" .. path)
    options.file_system:write(output_dir .. "/" .. path, data)
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
  if options.fail_on_problems and #report.problems > 0 then
    error(errors.BuildError({
      message = ("doc.build: %d problem(s):\n  %s"):format(#report.problems, table.concat(report.problems, "\n  ")),
      context = { problems = report.problems },
    }), 0)
  end
  return report
end

return M
