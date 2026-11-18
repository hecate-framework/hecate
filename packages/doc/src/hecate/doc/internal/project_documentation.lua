-- The generation of the documentation of a project, behind `hecate.doc.generate_project_documentation`: the
-- pages generated from the application (configuration reference), the third-party licences page and the code
-- reference, joined with the guides of the project and built into a site (documentation.md, "Documentation of
-- a project"). The paths are those of the conventional layout of a Hecate project, relative to `project_dir`.
global <const> require, type, ipairs, pairs, table, error, tostring

local core = require("hecate.core")
local build = require("hecate.doc.build")
local config_module = require("hecate.doc.config")
local errors = require("hecate.doc.errors")
local generated_page = require("hecate.doc.internal.generated_page")
local licenses = require("hecate.doc.licenses")
local project = require("hecate.doc.project")
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

---@class hecate.doc.ProjectLicensesOptions
---@field rocks_tree_dir? string  root of the installed rocks tree, relative to `project_dir` (default `lua_modules`): `<rocks_tree_dir>/lib/luarocks/rocks-<lua>/<rock>/<version>/<rock>-<version>.rockspec`, read through the file system, never run
---@field root_rocks? string[]  the rocks the project depends on: only they and their dependencies (resolved transitively) are listed; default: every installed rock
---@field audience? hecate.doc.Audience  audience of the page (default `maintainer`, OQ-144)
---@field include_bundled? boolean  list what the generated site bundles (fonts, brand marks, icon, Mermaid when a guide holds a diagram) with its licence texts (default true)

---@class hecate.doc.ProjectDocumentationOptions
---@field project_dir? string  directory of the project (default `.`, the current directory): every relative path below is relative to it, and LuaLS reads its `.luarc.json`
---@field guides_dir? string  directory of the guides, the content root of the site (default `docs`): one directory per locale (`<guides_dir>/en/*.md`) and optionally `public/`; the generated pages are written into it, as `<guides_dir>/<locale>/configuration.md`
---@field output_dir? string  directory the static site is written to (default `docs/dist`)
---@field site_configuration? hecate.doc.SiteConfig  the site configuration (title, audiences, locales, theme, ...) as a table; it wins over `site_configuration_path`
---@field site_configuration_path? string  Lua file that returns the site configuration (default `<guides_dir>/site.lua`); read with an empty environment, only when `site_configuration` is not given
---@field application? { configuration_schema: fun(self: table): table?, string[]? }  the application of the project (a `hecate.kernel.Application`, by duck-typing: only its method `configuration_schema` is called, `hecate.doc` does not depend on `kernel`): the configuration reference (a `maintainer` page) is generated from the schema of the configuration the application was given, and the secrets the application declares feed the redaction of their defaults. An application without a configuration adds nothing; without `application` there is no configuration reference
---@field package_name? string  Lua package name of the project, such as `shop`: asks for the code reference `reference/<package_name>/` of the annotated sources below `sources_dir` (skipped with a problem when LuaLS is missing); without it no code reference is generated. The reference lists the public symbols (pages of `user` audience); the pages of `*.internal` modules and of non-public classes are generated, as `maintainer` pages, only when the audiences include `maintainer`. When one audience is published (the default is `maintainer`), the site holds the whole reference and every page is labelled with that audience; with both, each page goes to the site of its audience
---@field sources_dir? string  directory of the Lua sources that the code reference documents, relative to `project_dir` (default `src`)
---@field language_server_path? string  the `lua-language-server` executable (default: found on the path)
---@field language_server_config_path? string  the `.luarc.json` LuaLS reads (default `<project_dir>/.luarc.json`). LuaLS runs the plugin that this file declares: the project must be trusted (OQ-142)
---@field licenses_page? boolean|hecate.doc.ProjectLicensesOptions  adds the third-party licences page (default: off); `true` reads the tree `lua_modules`
---@field content_locale? string  locale directory the generated pages are written to (default `default_locale` of the site configuration, "en")
---@field file_system? hecate.doc.FileSystem  where the project is read from and the site written to (default a `hecate.doc.SystemFileSystem`, which must run inside a reactor)
---@field clean_output_dir? boolean  empty `output_dir` first (only if a previous build wrote it)
---@field fail_on_problems? boolean  raise `hecate.doc.BuildError` when the report holds problems (broken links, a missing LuaLS, ...)
---@field last_updated? fun(path: string): string?  ISO 8601 date of the last change of a source file
---@field theme_file_system? hecate.doc.FileSystem  where the static files of the theme are read from (default: read with `io`)
---@field theme_files_dir? string  directory of the static files of the theme (default: the theme's own)

---@class hecate.doc.ProjectDocumentationReport : hecate.doc.BuildReport
---@field code? hecate.doc.ReferenceSiteReport  the code reference, when `package_name` was given

local function bad_option(field, expected)
  error(core.ArgumentError(("doc.generate_project_documentation: option `%s` must be %s"):format(field, expected)), 3)
end

local function is_absolute(path)
  return path:find("^/") ~= nil or path:find("^%a:") ~= nil
end

-- `path` below `directory`; an absolute path is kept, and the current directory adds nothing.
local function resolve(directory, path)
  if is_absolute(path) or directory == "." or directory == "" then return path end
  return directory:gsub("/+$", "") .. "/" .. path
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function check_path(options, field)
  local value = options[field]
  if value ~= nil and (type(value) ~= "string" or value == "") then bad_option(field, "a non-empty path (string)") end
end

local function validate(options)
  if type(options) ~= "table" then
    error(core.ArgumentError("doc.generate_project_documentation: expects an options table"), 3)
  end
  for _, field in ipairs({ "project_dir", "guides_dir", "output_dir", "sources_dir", "site_configuration_path",
    "language_server_config_path" }) do
    check_path(options, field)
  end
  if options.sources_dir ~= nil and is_absolute(options.sources_dir) then
    bad_option("sources_dir", "relative to `project_dir`")
  end
  if options.file_system ~= nil and type(options.file_system) ~= "table" then bad_option("file_system", "a hecate.doc.FileSystem") end
  if options.site_configuration ~= nil and type(options.site_configuration) ~= "table" then
    bad_option("site_configuration", "a table")
  end
  if options.application ~= nil and (type(options.application) ~= "table"
    or type(options.application.configuration_schema) ~= "function") then
    bad_option("application", "an object with a `configuration_schema` method (a hecate.kernel.Application)")
  end
  local licenses_option = options.licenses_page
  if licenses_option ~= nil and licenses_option ~= false and licenses_option ~= true then
    if type(licenses_option) ~= "table" then bad_option("licenses_page", "true or a table") end
    if licenses_option.rocks_tree_dir ~= nil and (type(licenses_option.rocks_tree_dir) ~= "string" or licenses_option.rocks_tree_dir == "") then
      bad_option("licenses_page.rocks_tree_dir", "a non-empty path (string)")
    end
    if licenses_option.root_rocks ~= nil then
      if type(licenses_option.root_rocks) ~= "table" then bad_option("licenses_page.root_rocks", "a list of rock names") end
      for _, name in ipairs(licenses_option.root_rocks) do
        if type(name) ~= "string" then bad_option("licenses_page.root_rocks", "a list of rock names (strings)") end
      end
    end
    local audience = licenses_option.audience
    if audience ~= nil and audience ~= "user" and audience ~= "maintainer" then
      bad_option("licenses_page.audience", '"user" or "maintainer"')
    end
    if licenses_option.include_bundled ~= nil and type(licenses_option.include_bundled) ~= "boolean" then
      bad_option("licenses_page.include_bundled", "a boolean")
    end
  end
  for _, field in ipairs({ "clean_output_dir", "fail_on_problems" }) do
    if options[field] ~= nil and type(options[field]) ~= "boolean" then bad_option(field, "a boolean") end
  end
  for _, field in ipairs({ "language_server_path", "theme_files_dir" }) do
    if options[field] ~= nil and type(options[field]) ~= "string" then bad_option(field, "a string") end
  end
  local package_name = options.package_name
  if package_name ~= nil and (type(package_name) ~= "string" or not package_name:match("^[%w_][%w_.%-]*$")
    or package_name:find("..", 1, true)) then
    bad_option("package_name", "a package name such as `shop`")
  end
end

local LICENSES_PAGE = "third-party-licences.md"
local GENERATED_PAGES = { "configuration.md", LICENSES_PAGE }

-- Generated files of the previous builds that this build no longer produces.
local function stale_files(fs, root, generated)
  local stale = {}
  for _, name in ipairs(GENERATED_PAGES) do
    if fs:exists(root .. "/" .. name) and not generated[name] and project.is_generated(fs:read(root .. "/" .. name)) then
      stale[#stale + 1] = name
    end
  end
  return stale
end

-- The schema and the secrets of the configuration, read from the application (the single source).
local function configuration_of(application)
  local secrets = {}
  if application == nil then return nil, secrets end
  local schema, declared_secrets = application:configuration_schema()
  if schema ~= nil and type(schema) ~= "table" then
    error(core.ArgumentError("doc.generate_project_documentation: `application:configuration_schema()` must return a JSON Schema table or nil"), 3)
  end
  for _, path in ipairs(type(declared_secrets) == "table" and declared_secrets or {}) do
    if type(path) == "string" then secrets[#secrets + 1] = path end
  end
  return schema, secrets
end

-- Whether a guide of the project holds a fenced `mermaid` block (CommonMark 4.5), in the Markdown files below the
-- guides directory: the licences page then names Mermaid.
local MAX_SCANNED_FILES = 5000
local function holds_diagram(fs, guides_dir)
  local function has_fence(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      if line:match("^ ? ? ?[`~][`~][`~]+%s*mermaid%f[%W]") then return true end
    end
    return false
  end
  local scanned = 0
  local function visit(directory)
    for _, entry in ipairs(fs:list(directory) or {}) do
      local path = directory .. "/" .. entry.name
      if entry.name:sub(1, 1) ~= "." and entry.name ~= "public" and not (fs.is_link and fs:is_link(path)) then
        if entry.is_directory then
          if visit(path) then return true end
        elseif entry.name:match("%.md$") and scanned < MAX_SCANNED_FILES then
          scanned = scanned + 1
          local text = fs:read(path)
          if text and has_fence(text) then return true end
        end
      end
    end
    return false
  end
  return visit(guides_dir:gsub("/+$", ""))
end

--- Generates the documentation site of a project. The generated pages are written below
--- `<guides_dir>/<locale>/` next to the guides, then the site is built into `output_dir`. Generated pages replace
--- the previous ones, and the generated pages that this build no longer produces are removed. Everything is checked
--- before anything is written: a generated page that would overwrite a file that is not generated (a hand-written
--- guide) raises `hecate.doc.BuildError` and leaves the tree untouched. A wrong option raises
--- `core.ArgumentError` naming it.
---@param options? hecate.doc.ProjectDocumentationOptions
---@return hecate.doc.ProjectDocumentationReport
function M.generate(options)
  options = options or {}
  validate(options)
  local defaults = M.DEFAULTS
  local project_dir = options.project_dir or defaults.project_dir
  local guides_dir = resolve(project_dir, options.guides_dir or defaults.guides_dir)
  local output_dir = resolve(project_dir, options.output_dir or defaults.output_dir)
  local fs = options.file_system or system_file_system()
  local site_configuration = options.site_configuration
  if site_configuration == nil then
    local path = options.site_configuration_path and resolve(project_dir, options.site_configuration_path)
      or (guides_dir:gsub("/+$", "") .. "/" .. defaults.site_configuration_file)
    site_configuration = build.load_config(path, fs)
  end
  local locale = options.content_locale
  if locale == nil then locale = site_configuration.default_locale or "en" end
  if type(locale) ~= "string" or not locale:match("^[%w%-]+$") then
    bad_option("content_locale", "a locale code made of letters, digits and `-`")
  end
  -- The audiences are checked before anything is written (a wrong one raises `core.ConfigurationError`);
  -- a project site publishes the `maintainer` audience unless it asks for more (OQ-144).
  local audiences = config_module.normalise(site_configuration).audiences --[[@as hecate.doc.Audience[] ]]
  local maintainer = false
  for _, audience in ipairs(audiences) do maintainer = maintainer or audience == "maintainer" end
  -- The code reference is labelled by audience (public symbols `user`, internals `maintainer`) when both audiences
  -- are published; a site that publishes one audience holds the whole reference, labelled with it.
  local label = #audiences == 1 and audiences[1] or true
  local root = guides_dir:gsub("/+$", "") .. "/" .. locale
  local generated = {}
  local schema, secrets = configuration_of(options.application)
  if schema then generated["configuration.md"] = project.configuration_page(schema, { secrets = secrets }) end
  local licence_problems = {}
  if options.licenses_page then
    ---@type hecate.doc.ProjectLicensesOptions
    local licence = options.licenses_page == true and {} or options.licenses_page --[[@as hecate.doc.ProjectLicensesOptions]]
    local model = licenses.read(fs, {
      tree = resolve(project_dir, licence.rocks_tree_dir or defaults.rocks_tree_dir), roots = licence.root_rocks,
    })
    licence_problems = model.problems
    local bundled = licence.include_bundled ~= false and licenses.bundled({
      diagrams = holds_diagram(fs, guides_dir), theme_fs = options.theme_file_system,
      theme_directory = options.theme_files_dir,
    }) or nil
    generated[LICENSES_PAGE] = licenses.markdown(model, generated_page.front("Third-party licences",
      "The rocks and libraries the project uses and what the site bundles, with their licences.", 60,
      licence.audience or "maintainer"), bundled)
  end
  for _, path in ipairs(sorted_keys(generated)) do
    local target = root .. "/" .. path
    if fs:exists(target) and not project.is_generated(fs:read(target)) then
      error(errors.BuildError({
        message = ("doc.generate_project_documentation: %s exists and is not generated; move it, or rename the generated page"):format(target),
        context = { path = target },
      }), 0)
    end
  end
  for _, path in ipairs(stale_files(fs, root, generated)) do fs:remove_tree(root .. "/" .. path) end
  for _, path in ipairs(sorted_keys(generated)) do fs:write(root .. "/" .. path, generated[path]) end
  local code_report
  if options.package_name then
    code_report = require("hecate.doc.reference_site").run({
      root = project_dir, packages = { options.package_name },
      layout = (options.sources_dir or defaults.sources_dir):gsub("%%", "%%%%"), out = root, fs = fs,
      executable = options.language_server_path,
      config = options.language_server_config_path and resolve(project_dir, options.language_server_config_path) or nil,
      internal = maintainer, label_audiences = label,
    })
  end
  local report = build.build({
    config = site_configuration, source = guides_dir, out = output_dir, fs = fs, clean = options.clean_output_dir,
    strict = options.fail_on_problems, last_updated = options.last_updated, theme_fs = options.theme_file_system,
    theme_directory = options.theme_files_dir,
  }) --[[@as hecate.doc.ProjectDocumentationReport]]
  for _, problem in ipairs(licence_problems) do report.problems[#report.problems + 1] = problem end
  if code_report then
    report.code = code_report
    for _, problem in ipairs(code_report.problems) do report.problems[#report.problems + 1] = problem end
    if code_report.skipped then report.problems[#report.problems + 1] = code_report.skipped end
  end
  return report
end

return M
