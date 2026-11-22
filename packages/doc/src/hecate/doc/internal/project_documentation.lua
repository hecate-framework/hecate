-- The generation of the documentation of a project, behind `hecate.doc.generate_project_documentation`: the
-- pages generated from the application (configuration reference), the third-party licences page and the code
-- reference, joined with the guides of the project and built into sites, one per audience (documentation.md,
-- "Documentation of a project"): the guides of an audience are a content tree of their own, `<guides_dir>/<audience>/`,
-- built by the plain builder into `<output_dir>/<audience>/` (OQ-144, owner decision of 2026-11-21). The paths are those
-- of the conventional layout of a Hecate project, relative to `project_dir`.
global <const> require, type, ipairs, pairs, table, error, tostring, string, math

local core = require("hecate.core")
local build = require("hecate.doc.build")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local generated_page = require("hecate.doc.internal.generated_page")
local html = require("hecate.doc.internal.html")
local options_module = require("hecate.doc.internal.options")
local paths = require("hecate.doc.internal.paths")
local portable = require("hecate.doc.internal.portable_name")
local safe_write = require("hecate.doc.internal.safe_write")
-- `hecate.doc.licences`: our own identifiers use British spelling; American `license` stays only in external names
-- (the rockspec field `description.license`, SPDX, the task `check-licenses`, `THIRD_PARTY_NOTICES`).
local licences = require("hecate.doc.licences")
local project = require("hecate.doc.project")
local Site = require("hecate.doc.site")
local system_file_system = require("hecate.doc.system_file_system")

local M = {}

--- The defaults of the conventional layout of a Hecate project (OQ-143: `docs/` and `docs/dist` are not
--- specified by the layout of `developer-experience.md`; they are the conservative choice, as in `examples/hello`).
M.DEFAULTS = {
  project_dir = ".",
  sources_dir = "src",
  guides_dir = "docs",
  output_dir = "docs/dist",
  rocks_tree_dir = "lua_modules",
  site_configuration_file = "site.lua", -- below `guides_dir`
  luarc_file = ".luarc.json",           -- below `project_dir`
}

---@class hecate.doc.ProjectLicencesOptions
---@field rocks_tree_dir? string  root of the installed rocks tree, relative to `project_dir` (default `lua_modules`): `<rocks_tree_dir>/lib/luarocks/rocks-<lua>/<rock>/<version>/<rock>-<version>.rockspec`, read through the file system, never run
---@field root_rocks? string[]  the rocks the project depends on: only they and their dependencies (resolved transitively) are listed; default: every installed rock
---@field audience? hecate.doc.Audience  the tree the page is written into: one of the built `audiences` (default `maintainer` when it is built, otherwise the first audience built)
---@field include_bundled? boolean  list what the generated site bundles (fonts, brand marks, icon, Mermaid when a guide holds a diagram) with its licence texts (default true)

---@class hecate.doc.ProjectDocumentationOptions
---@field project_dir? string  directory of the project (default `.`, the current directory): every relative path below is relative to it, and LuaLS reads its `.luarc.json`
---@field guides_dir? string  directory of the guides (default `docs`): one content tree per audience, `<guides_dir>/<audience>/` (`user`, `maintainer`), each laid out as the tree of a plain site (one directory per locale, `<guides_dir>/<audience>/en/*.md`, and optionally `<guides_dir>/<audience>/public/`); the generated pages are written into the trees, as `<guides_dir>/maintainer/<locale>/configuration.md`. `site.lua` is `<guides_dir>/site.lua`
---@field audiences? hecate.doc.Audience[]  the audience trees to build, each into its own site (default `{ "maintainer" }`): a tree that is not listed is not built and is no error; a listed tree that does not exist is a problem (add `<guides_dir>/<audience>/<default locale>/index.md`)
---@field output_dir? string  directory the sites are written to (default `docs/dist`, below the guides): one site per audience in `<output_dir>/<audience>/`. It may not be `guides_dir` or `project_dir`, hold either of them, or overlap `sources_dir`: the build rewrites it, and empties it with `clean_output_dir`
---@field site_configuration? hecate.doc.SiteConfiguration  the site configuration (title, locales, ...) as a table, the same for every audience site; giving it together with `site_configuration_path` is an error
---@field site_configuration_path? string  Lua file that returns the site configuration, relative to `project_dir` like every other path (the default, `site.lua` below `guides_dir`, is below the guides); read with an empty environment under the limits of `hecate.doc.load_site_configuration`
---@field application? { configuration_schema: fun(self: table): table? }  the application of the project (a `hecate.kernel.Application`, by duck-typing: only its method `configuration_schema` is called, `hecate.doc` does not depend on `kernel`): the configuration reference (a page of the `maintainer` tree, written only when `maintainer` is built) is generated from the schema of the configuration the application was given. The schema is the single source, secrets included: a key marked `writeOnly: true` or `format: "password"` never shows its default. An application without a configuration adds nothing; without `application` there is no configuration reference
---@field package_name? string  Lua package name of the project, such as `shop`: asks for the code reference `reference/<package_name>/` of the annotated sources below `sources_dir` (skipped with a problem when LuaLS is missing); without it no code reference is generated. The reference lists the public symbols (pages of the `user` tree); the pages of `*.internal` modules and of non-public classes are generated, into the `maintainer` tree, only when `maintainer` is built. When one audience is built (the default is `maintainer`), its tree holds the whole reference; with both, each page goes to the tree of its audience and the pages of one tree never link to the other
---@field sources_dir? string  directory of the Lua sources that the code reference documents, relative to `project_dir` (default `src`); never absolute: LuaLS runs the plugins that the configuration files of the directory it documents declare, so only a tree below the project is documented
---@field language_server_path? string  the `lua-language-server` executable (default: found on the path)
---@field language_server_config_path? string  the `.luarc.json` LuaLS reads, passed as `--configpath` (default `<project_dir>/.luarc.json`, which `hecate.doc.reference_site.run` passes whether the file exists or not). LuaLS runs the plugin that a configuration declares, this file and those it finds in the directory it documents: the project must be trusted
---@field licences_page? boolean|hecate.doc.ProjectLicencesOptions  adds the third-party licences page (default: off); `true` reads the tree `lua_modules`
---@field content_locale? string  locale directory the generated pages are written to: a locale of the site configuration (default its `default_locale`, "en")
---@field file_system? hecate.doc.FileSystem  where the project is read from and the site written to (default a `hecate.doc.SystemFileSystem`, which must run inside a reactor)
---@field clean_output_dir? boolean  empty `output_dir` first (only if a previous build wrote it)
---@field fail_on_problems? boolean  raise one `hecate.doc.BuildError` that lists every problem of the report (a missing audience tree, broken links, a missing LuaLS, the problems of the licences page and of the code reference, ...), after the sites are written
---@field last_updated? fun(path: string): string?  ISO 8601 date of the last change of a source file
---@field theme_file_system? hecate.doc.FileSystem  where the static files of the theme are read from (default: read with `io`)
---@field theme_files_dir? string  directory of the static files of the theme (default: the theme's own)

---@class hecate.doc.ProjectSiteReport
---@field audience hecate.doc.Audience
---@field directory string  directory of the site below `output_dir` (the audience)
---@field files integer  files written to the site
---@field bytes integer
---@field locales table<string, { pages: integer, fallbacks: integer }>
---@field problems string[]  problems of this site, sorted and unique

---@class hecate.doc.ProjectDocumentationReport : hecate.doc.BuildReport
---@field sites hecate.doc.ProjectSiteReport[]  one entry per audience tree built, in the order of `audiences`; `files`, `bytes` and `locales` of the report add up the sites (and the two files at the root of `output_dir`), `problems` holds the problems of each site prefixed with `<audience> site: `
---@field code? hecate.doc.ReferenceSiteReport  the code reference, when `package_name` was given

local WHO = "doc.generate_project_documentation"

-- The limits of the scan for diagrams, which walks a tree that is data of the project (exposed so that a test can lower them).
M.LIMITS = { scanned_files = 5000, depth = 32 }

local function clean(path)
  return (paths.separators(path):gsub("/+$", ""))
end

local function resolve(directory, path)
  return paths.resolve(directory, clean(path))
end

-- The audiences to build: the option, or `maintainer` (owner decision of 2026-11-21: maintainers by default).
local function audiences_of(options)
  return options.audiences or { "maintainer" }
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local PATH_OPTIONS = { "project_dir", "guides_dir", "output_dir", "sources_dir", "site_configuration_path",
  "language_server_config_path", "language_server_path", "theme_files_dir", "file_system", "theme_file_system",
  "last_updated", "site_configuration", "clean_output_dir", "fail_on_problems" }

-- Checks the options and returns the first mistake as `field, expected`, or nothing. Raised by `generate` at one place, so
-- that the position of the error is the call of the user.
local function validate(options)
  options_module.check(WHO, "generate_project_documentation", options, options_module.PROJECT_DOCUMENTATION, 4)
  local field, expected = options_module.invalid(options, PATH_OPTIONS)
  if field then return field, expected end
  local sources_dir = options.sources_dir
  if sources_dir ~= nil and paths.is_absolute(sources_dir) then
    return "sources_dir", "relative to `project_dir`: LuaLS runs the plugins that the configuration files of the directory it documents declare, so only a tree below the project is documented"
  end
  if options.site_configuration ~= nil and options.site_configuration_path ~= nil then
    return "site_configuration_path", "absent when `site_configuration` is given: the table wins and the file would be ignored; give one of them"
  end
  if options.application ~= nil and (type(options.application) ~= "table"
    or type(options.application.configuration_schema) ~= "function") then
    return "application", "an object with a `configuration_schema` method (a hecate.kernel.Application)"
  end
  local audiences = options.audiences
  if audiences ~= nil then
    local expected = 'a non-empty list of "user" and "maintainer", each once (the audience trees to build)'
    if type(audiences) ~= "table" or #audiences == 0 then return "audiences", expected end
    local seen, count = {}, 0
    for index, name in pairs(audiences) do
      count = count + 1
      if math.type(index) ~= "integer" or not config_module.AUDIENCES[name] or seen[name] then return "audiences", expected end
      seen[name] = true
    end
    if count ~= #audiences then return "audiences", expected end
  end
  local licences_option = options.licences_page
  if licences_option ~= nil and licences_option ~= false and licences_option ~= true then
    if type(licences_option) ~= "table" then return "licences_page", "true or a table" end
    options_module.check(WHO .. " (licences_page)", "licences_page", licences_option, options_module.LICENCES_PAGE, 4)
    if licences_option.rocks_tree_dir ~= nil and (type(licences_option.rocks_tree_dir) ~= "string" or licences_option.rocks_tree_dir == "") then
      return "licences_page.rocks_tree_dir", "a non-empty path (string)"
    end
    if licences_option.root_rocks ~= nil then
      if type(licences_option.root_rocks) ~= "table" then return "licences_page.root_rocks", "a list of rock names" end
      for _, name in ipairs(licences_option.root_rocks) do
        if type(name) ~= "string" then return "licences_page.root_rocks", "a list of rock names (strings)" end
      end
    end
    local audience = licences_option.audience
    if audience ~= nil then
      local listed = false
      for _, name in ipairs(audiences_of(options)) do listed = listed or name == audience end
      if audience ~= "user" and audience ~= "maintainer" then return "licences_page.audience", '"user" or "maintainer"' end
      if not listed then
        return "licences_page.audience", ('one of the audiences listed in `audiences` (%s): the page is written into that tree'):format(
          table.concat(audiences_of(options), ", "))
      end
    end
    if licences_option.include_bundled ~= nil and type(licences_option.include_bundled) ~= "boolean" then
      return "licences_page.include_bundled", "a boolean"
    end
  end
  local package_name = options.package_name
  if package_name ~= nil and (type(package_name) ~= "string" or not package_name:match("^[%w_][%w_.%-]*$")
    or package_name:find("..", 1, true)) then
    return "package_name", "a package name such as `shop` (letters, digits, `_`, `-` and inner dots: no separator, no `..`, no leading dot)"
  end
  return nil
end

local LICENCES_PAGE = "third-party-licences.md"
local GENERATED_PAGES = { "configuration.md", LICENCES_PAGE }

-- Generated files of the previous builds that this build no longer produces. A link is never one of them: it is not ours.
local function stale_files(fs, root, generated)
  local stale = {}
  for _, name in ipairs(GENERATED_PAGES) do
    local path = root .. "/" .. name
    if not generated[name] and not (fs.is_link and fs:is_link(path)) and fs:exists(path)
      and generated_page.is_generated(fs:read(path)) then
      stale[#stale + 1] = name
    end
  end
  return stale
end

-- The schema of the configuration, read from the application (the single source: its `writeOnly` marks are the secrets).
local function configuration_of(application)
  if application == nil then return nil end
  local schema = application:configuration_schema()
  if schema ~= nil and type(schema) ~= "table" then
    error(core.ArgumentError("doc.generate_project_documentation: `application:configuration_schema()` must return a JSON Schema table or nil"), 3)
  end
  return schema
end

-- Whether a guide of the project holds a fenced `mermaid` block (CommonMark 4.5), in the Markdown files below the
-- guides directory: the licences page then names Mermaid. The walk skips hidden entries, `public/`, the output directory
-- and every link, and stops at a depth and at a number of files: it returns a problem when it stopped short.
local function holds_diagram(fs, guides_dir, output_dir)
  local function has_fence(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      if line:match("^ ? ? ?[`~][`~][`~]+%s*mermaid%f[%W]") then return true end
    end
    return false
  end
  local scanned, stopped = 0, nil
  local function visit(directory, depth)
    for _, entry in ipairs(fs:list(directory) or {}) do
      local path = directory .. "/" .. entry.name
      local skipped = entry.name:sub(1, 1) == "." or entry.name == "public" or entry.is_link == true
        or (fs.is_link ~= nil and fs:is_link(path)) or paths.relation(path, output_dir) == "same"
      if not skipped then
        if entry.is_directory then
          if depth + 1 > M.LIMITS.depth then
            stopped = stopped or ("the scan for diagrams stopped: %s is deeper than %d levels; Mermaid is named in the licences only if a diagram is found before"):format(path, M.LIMITS.depth)
          elseif visit(path, depth + 1) then
            return true
          end
        elseif portable.is_markdown(entry.name) then
          if scanned >= M.LIMITS.scanned_files then
            stopped = stopped or ("the scan for diagrams stopped after %d Markdown files; Mermaid is named in the licences only if a diagram is found before"):format(M.LIMITS.scanned_files)
          else
            scanned = scanned + 1
            local text = fs:read(path)
            if text and has_fence(text) then return true end
          end
        end
      end
    end
    return false
  end
  local found = visit(clean(guides_dir), 0)
  return found, (not found) and stopped or nil
end

local function missing_site_configuration(path, default_path)
  local text = ("doc.generate_project_documentation: cannot read the site configuration %s: the file does not exist"):format(path)
  if default_path then
    text = text .. (". The default path is `site.lua` below `guides_dir`: create it (a Lua file that returns a table with at least a `title`), "
      .. "give `site_configuration_path` (relative to `project_dir`), or pass `site_configuration = { title = ... }`")
  end
  error(errors.BuildError({ message = text, context = { path = path } }), 0)
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

-- The page at the root of `output_dir`: it leads to the first site built.
local function root_redirect(config, directory)
  local target = config.base_path .. directory .. "/" .. config.default_locale .. "/"
  return ("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>%s</title>\n"
    .. "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n<link rel=\"canonical\" href=\"%s\">\n</head>\n"
    .. "<body>\n<p><a href=\"%s\">%s</a></p>\n</body>\n</html>\n"):format(
    html.escape(config.default_locale), html.escape(config.title), html.escape(target),
    html.escape(config.site_origin and (config.site_origin .. target) or target), html.escape(target), html.escape(config.title))
end

-- The site configuration of one audience site: the configuration of the project, the same for every audience (per-audience
-- overrides are out of scope), with the two keys that depend on where the tree and its output lie. The site is served
-- below `<base_path><audience>/`, and the source of a page is `<audience>/<path below the tree>` in the repository.
local function site_configuration_of(raw, normalised, audience)
  local own = {}
  for key, value in pairs(raw) do own[key] = value end
  own.base_path = normalised.base_path .. audience .. "/"
  if normalised.edit_link_template then
    own.edit_link_template = normalised.edit_link_template:gsub("{path}", function() return audience .. "/{path}" end)
  end
  return own
end

--- Generates the documentation sites of a project, one per audience. Each audience is a content tree of its own,
--- `<guides_dir>/<audience>/<locale>/`, with its own `public/`; the trees listed in `audiences` (default `maintainer`) are
--- built by the plain builder into `<output_dir>/<audience>/`, with their own navigation, search index, sitemap, `llms.txt`,
--- theme files and 404 page, and nothing of the other audience. The generated pages are written below
--- `<guides_dir>/<audience>/<locale>/` next to the guides: the configuration reference and the licences page into the
--- `maintainer` tree, the code reference into the `user` tree (public symbols) and the `maintainer` tree (internals), or all of
--- it into the one tree built. Generated pages replace the previous ones, and the generated pages that this build no longer
--- produces are removed. Everything is checked before anything is written: a generated page that would overwrite a file that
--- is not generated (a hand-written guide), or lie behind a symbolic link, raises `hecate.doc.BuildError` and leaves the
--- trees untouched. A wrong option, an option that is not on the list (an old name, a typo) and an `output_dir` that is
--- `guides_dir`, `project_dir` or holds either, or overlaps `sources_dir`, raise `hecate.core.ArgumentError` naming it
--- (`context.argument`). `\` is a separator in every path option. A listed audience whose tree does not exist is a problem
--- and is not built. With `fail_on_problems`, the sites are written and one `hecate.doc.BuildError` lists every problem.
---@param options? hecate.doc.ProjectDocumentationOptions
---@return hecate.doc.ProjectDocumentationReport
function M.generate(options)
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError({ message = WHO .. ": expects an options table", context = { argument = "options" } }), 2)
  end
  options = options or {}
  local field, expected = validate(options)
  if field then options_module.refuse(WHO, field, expected or "valid", 3) end
  local defaults = M.DEFAULTS
  local project_dir = clean(options.project_dir or defaults.project_dir)
  local guides_dir = resolve(project_dir, options.guides_dir or defaults.guides_dir)
  local output_dir = resolve(project_dir, options.output_dir or defaults.output_dir)
  local sources_dir = resolve(project_dir, options.sources_dir or defaults.sources_dir)
  -- The build rewrites the output (and empties it with `clean_output_dir`): it may lie below the guides and the project, which is
  -- the default layout, but never be them, hold them, or overlap the sources.
  local function overlap(other, name, relations)
    local relation = paths.relation(other, output_dir)
    if relation and relations[relation] then
      options_module.refuse(WHO, "output_dir", ("a directory that is not `%s` and does not overlap it (`output_dir` %s, `%s` %s)")
        :format(name, output_dir, name, other), 3)
    end
  end
  if paths.is_root(output_dir) then options_module.refuse(WHO, "output_dir", "a directory, not the root of a file system", 3) end
  overlap(guides_dir, "guides_dir", { same = true, inside = true })
  overlap(project_dir, "project_dir", { same = true, inside = true })
  overlap(sources_dir, "sources_dir", { same = true, inside = true, contains = true })
  local fs = options.file_system or system_file_system()
  local site_configuration = options.site_configuration
  if site_configuration == nil then
    local explicit = options.site_configuration_path
    local path = explicit and resolve(project_dir, explicit) or (guides_dir:gsub("/+$", "") .. "/" .. defaults.site_configuration_file)
    if fs:read(path) == nil then missing_site_configuration(path, explicit == nil) end
    site_configuration = build.load_site_configuration(fs, path)
  end
  -- The site configuration is checked before anything is written (an old key, such as the removed `audiences`, raises
  -- `core.ConfigurationError`).
  local normalised = config_module.normalise(site_configuration)
  local locale = options.content_locale
  if locale == nil then locale = normalised.default_locale end
  local known = {}
  for _, entry in ipairs(normalised.locales) do known[#known + 1] = entry.code end
  local listed = false
  for _, code in ipairs(known) do listed = listed or code == locale end
  if type(locale) ~= "string" or not locale:match("^[%w%-]+$") or not listed then
    options_module.refuse(WHO, "content_locale", ("a locale of the site configuration (%s)"):format(table.concat(known, ", ")), 3)
  end
  local problems = {}
  -- The trees: a listed audience whose tree does not exist is a problem (and is not built); a tree that is not listed is not
  -- built and is no error.
  local trees, built, has = {}, {}, {}
  for _, audience in ipairs(audiences_of(options)) do
    local tree = guides_dir:gsub("/+$", "") .. "/" .. audience
    if fs:list(tree) == nil then
      problems[#problems + 1] = ("audience %q is listed in `audiences` but its content tree %s does not exist: add %s/%s/index.md "
        .. "(the home page of that site), or leave %q out of `audiences`"):format(audience, tree, tree, normalised.default_locale, audience)
    else
      trees[audience] = tree
      built[#built + 1] = audience
      has[audience] = true
    end
  end
  -- The pages generated from the project, per tree: the configuration reference and the licences page.
  local generated = {}
  for _, audience in ipairs(built) do generated[audience] = {} end
  local schema = configuration_of(options.application)
  if schema and has.maintainer then generated.maintainer["configuration.md"] = project.configuration_page(schema) end
  if options.licences_page then
    ---@type hecate.doc.ProjectLicencesOptions
    local licence = options.licences_page == true and {} or options.licences_page --[[@as hecate.doc.ProjectLicencesOptions]]
    local target = licence.audience or (has.maintainer and "maintainer" or built[1])
    if has[target] then
      local model = licences.read(fs, {
        rocks_tree_dir = resolve(project_dir, licence.rocks_tree_dir or defaults.rocks_tree_dir),
        root_rocks = licence.root_rocks,
      })
      for _, problem in ipairs(model.problems) do problems[#problems + 1] = problem end
      -- The site bundles Mermaid when one of its own guides holds a diagram.
      local diagrams, scan_problem = holds_diagram(fs, trees[target], output_dir)
      if scan_problem then problems[#problems + 1] = scan_problem end
      local bundled = licence.include_bundled ~= false and licences.bundled({
        diagrams = diagrams, theme_file_system = options.theme_file_system, theme_files_dir = options.theme_files_dir,
      }) or nil
      generated[target][LICENCES_PAGE] = licences.markdown(model, generated_page.front("Third-party licences",
        "The rocks and libraries the project uses and what the site bundles, with their licences.", 60), bundled)
    end
  end
  local guard = safe_write.guard(fs, guides_dir)
  for _, audience in ipairs(built) do
    local root = trees[audience] .. "/" .. locale
    for _, path in ipairs(sorted_keys(generated[audience])) do
      local target = root .. "/" .. path
      guard(target) -- a link is never written through: a dangling one would create (or truncate) the file it points to
      if fs:exists(target) and not generated_page.is_generated(fs:read(target)) then
        error(errors.BuildError({
          message = ("doc.generate_project_documentation: %s exists and is not generated; move it, or rename the generated page"):format(target),
          context = { path = target },
        }), 0)
      end
    end
  end
  for _, audience in ipairs(built) do
    local root = trees[audience] .. "/" .. locale
    for _, path in ipairs(stale_files(fs, root, generated[audience])) do fs:remove_tree(root .. "/" .. path) end
    for _, path in ipairs(sorted_keys(generated[audience])) do fs:write(root .. "/" .. path, generated[audience][path]) end
  end
  local code_report
  if options.package_name and #built > 0 then
    local reference_options = {
      project_dir = project_dir, packages = { options.package_name },
      sources_dir_pattern = clean(options.sources_dir or defaults.sources_dir):gsub("%%", "%%%%"),
      file_system = fs, language_server_path = options.language_server_path,
      language_server_config_path = options.language_server_config_path
        and resolve(project_dir, options.language_server_config_path) or nil,
    }
    if has.user and has.maintainer then
      -- Two trees: public symbols into the user tree, internals into the maintainer tree; no page links to the other tree.
      reference_options.audience_locale_dirs = { user = trees.user .. "/" .. locale, maintainer = trees.maintainer .. "/" .. locale }
    else
      -- One tree holds the whole reference; the internals are generated only for the maintainer tree.
      reference_options.locale_dir = trees[built[1]] .. "/" .. locale
      reference_options.internal = has.maintainer == true
    end
    code_report = require("hecate.doc.reference_site").run(reference_options)
  end
  -- Every tree is read and rendered before anything is written to the output: a tree that fails leaves no partial output. The
  -- sites do not fail on their problems here: they are merged with those of the licences page and of the code reference, and
  -- `fail_on_problems` raises once, for all of them.
  local prepared = {}
  for _, audience in ipairs(built) do
    prepared[#prepared + 1] = build.prepare({
      site_configuration = site_configuration_of(site_configuration, normalised, audience), guides_dir = trees[audience],
      output_dir = output_dir .. "/" .. audience, file_system = fs, last_updated = options.last_updated,
      theme_file_system = options.theme_file_system, theme_files_dir = options.theme_files_dir,
    })
  end
  local report = { files = 0, bytes = 0, locales = {}, problems = {}, sites = {} } --[[@as hecate.doc.ProjectDocumentationReport]]
  for _, entry in ipairs(normalised.locales) do report.locales[entry.code] = { pages = 0, fallbacks = 0 } end
  if #built > 0 then
    if options.clean_output_dir then build.clean_output_dir(fs, output_dir) end
    local output_guard = safe_write.guard(fs, output_dir)
    local function put(path, data)
      output_guard(output_dir .. "/" .. path)
      fs:write(output_dir .. "/" .. path, data)
      report.files = report.files + 1
      report.bytes = report.bytes + #data
    end
    -- First, so that an interrupted build can still be cleaned by the next one.
    put(Site.MARKER, "Written by hecate.doc. This directory is emptied by builds that ask for a clean output.\n")
    put("index.html", root_redirect(normalised, built[1]))
    for index, audience in ipairs(built) do
      local site_report = prepared[index].write()
      report.sites[index] = { audience = audience, directory = audience, files = site_report.files, bytes = site_report.bytes,
        locales = site_report.locales, problems = site_report.problems }
      report.files = report.files + site_report.files
      report.bytes = report.bytes + site_report.bytes
      for code, entry in pairs(site_report.locales) do
        report.locales[code].pages = report.locales[code].pages + entry.pages
        report.locales[code].fallbacks = report.locales[code].fallbacks + entry.fallbacks
      end
      for _, problem in ipairs(site_report.problems) do problems[#problems + 1] = ("%s site: %s"):format(audience, problem) end
    end
  end
  if code_report then
    report.code = code_report
    for _, problem in ipairs(code_report.problems) do problems[#problems + 1] = problem end
    if code_report.skipped then problems[#problems + 1] = code_report.skipped end
  end
  report.problems = sorted_unique(problems)
  if options.fail_on_problems and #report.problems > 0 then
    error(errors.BuildError({
      message = ("%s: %d problem(s):\n  %s"):format(WHO, #report.problems, table.concat(report.problems, "\n  ")),
      context = { problems = report.problems },
    }), 0)
  end
  return report
end

return M
