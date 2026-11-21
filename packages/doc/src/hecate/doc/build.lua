-- The build entry point: content tree in, static site out.
global <const> require, type, error, ipairs, table, load, tostring

local core = require("hecate.core")
local errors = require("hecate.doc.errors")
local options_module = require("hecate.doc.internal.options")
local paths = require("hecate.doc.internal.paths")
local portable = require("hecate.doc.internal.portable_name")
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
---@field locales table<string, { pages: integer, fallbacks: integer }>
---@field problems string[]  broken links, missing titles and similar, sorted and unique

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
  local entry = { pages = 0, fallbacks = 0 }
  for _, page in ipairs(site:pages(code)) do
    entry.pages = entry.pages + 1
    if page.fallback then entry.fallbacks = entry.fallbacks + 1 end
  end
  return entry
end

--- Empties `output_dir`, only if a previous build wrote it (it holds the marker file) or it is empty. Refuses a symbolic
--- link: the directory must be the real one.
---@param fs hecate.doc.FileSystem
---@param output_dir string
function M.clean_output_dir(fs, output_dir)
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

---@class hecate.doc.PreparedBuild
---@field site hecate.doc.Site  the loaded site
---@field write fun(): hecate.doc.BuildReport  empties the output directory when asked, writes the site and returns the report (problems are not raised)

-- The error of a wrong option points at the caller of the API function that called this one (`level` 4 of `error`).
local function prepare(options)
  options_module.check("doc.build", "build", options, options_module.BUILD, 4)
  local field, expected = options_module.invalid(options, { "guides_dir", "output_dir", "file_system", "theme_file_system",
    "theme_files_dir", "last_updated", "site_configuration", "clean_output_dir", "fail_on_problems" })
  if field then options_module.refuse("doc.build", field, expected or "valid", 4) end
  -- `\` is a separator at this entry point; below it everything works with `/`.
  local output_dir = paths.separators(options.output_dir):gsub("/+$", "")
  if output_dir == "" or paths.is_root(output_dir) or paths.is_root(output_dir .. "/") then
    options_module.refuse("doc.build", "output_dir", "a directory, not the root of a file system", 4)
  end
  local guides_dir = paths.separators(options.guides_dir or "")
  -- The output is rewritten, and emptied with `clean_output_dir`: it may lie below the guides (the default layout of a
  -- project is `docs/dist` below `docs`), but it is never the guides themselves or a directory that holds them.
  local relation = paths.relation(guides_dir, output_dir)
  if relation == "same" or relation == "inside" then
    options_module.refuse("doc.build", "output_dir", ("a directory that is not `guides_dir` and does not hold it (`output_dir` %s, `guides_dir` %s)")
      :format(options.output_dir, options.guides_dir), 4)
  end
  -- What `Site` is given: its own options, not those of the output.
  local site_options = {}
  for _, key in ipairs(options_module.SITE) do site_options[key] = options[key] end
  -- The content tree is read before anything is written: a failing build leaves no partial output.
  local site = Site(site_options):load()
  local fs = options.file_system
  local function write()
    if options.clean_output_dir then M.clean_output_dir(fs, output_dir) end
    local bytes, files = 0, 0
    local guard = safe_write.guard(fs, output_dir)
    files = site:emit(function(path, data)
      -- A path of 260 characters or more does not open on Windows (a problem, an error under `fail_on_problems`).
      local too_long = portable.path_limit_problem(output_dir .. "/" .. path)
      if too_long then site.problems[#site.problems + 1] = too_long end
      bytes = bytes + #data
      guard(output_dir .. "/" .. path)
      fs:write(output_dir .. "/" .. path, data)
    end)
    local report = { files = files, bytes = bytes, locales = {}, problems = sorted_unique(site.problems) }
    for _, locale in ipairs(site.site_configuration.locales) do report.locales[locale.code] = locale_entry(site, locale.code) end
    return report
  end
  return { site = site, write = write }
end

--- The first half of `build`: checks the options and reads and renders the content tree (`Site:load`), and returns what the
--- second half needs. Nothing is written until `write` is called, so that a caller that builds several trees (the
--- documentation of a project: one per audience) can load them all before it writes any. `build` is `prepare`, `write`, and
--- the raise of `fail_on_problems`.
---@param options hecate.doc.BuildOptions
---@return hecate.doc.PreparedBuild
function M.prepare(options)
  if type(options) ~= "table" or type(options.output_dir) ~= "string" or options.output_dir == "" then
    error(core.ArgumentError("doc.build: expects options with an `output_dir` directory"), 2)
  end
  return prepare(options)
end

--- Builds a site: reads `<guides_dir>/<locale>/**/*.md`, renders every page for every locale
--- with the theme, writes the search indexes, the theme files and the other static files
--- to `options.output_dir`, and returns a report. The output is deterministic. The content tree is one site: a
--- documentation site is built from one tree (`generate_project_documentation` calls this builder once per audience
--- tree, OQ-144).
---@param options hecate.doc.BuildOptions
---@return hecate.doc.BuildReport
function M.build(options)
  if type(options) ~= "table" or type(options.output_dir) ~= "string" or options.output_dir == "" then
    error(core.ArgumentError("doc.build: expects options with an `output_dir` directory"), 2)
  end
  local report = prepare(options).write()
  if options.fail_on_problems and #report.problems > 0 then
    error(errors.BuildError({
      message = ("doc.build: %d problem(s):\n  %s"):format(#report.problems, table.concat(report.problems, "\n  ")),
      context = { problems = report.problems },
    }), 0)
  end
  return report
end

return M
