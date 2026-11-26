-- Site configuration: validation and defaults for the table returned by `site.lua`.
global <const> require, type, ipairs, pairs, next, error, tostring, table, string, math

local core = require("hecate.core")
local html = require("hecate.doc.internal.html")
local options = require("hecate.doc.internal.options")

--- Validation and defaults of the site configuration.
---@class hecate.doc.config
local M = {}

---@class hecate.doc.Locale
---@field code string  directory name and URL prefix ("en", "fr")
---@field label string  name shown in the locale switch, in that language ("Français")
---@field lang string  BCP 47 tag for the `lang` attribute (defaults to `code`)

---@alias hecate.doc.Audience "user"|"maintainer"  who a content tree is written for (glossary: audience, user documentation, maintainer documentation): `generate_project_documentation` builds one tree per audience

---@alias hecate.doc.Text string|table<string, string>  a string, or one string per locale code

---@class hecate.doc.TopLinkEntry
---@field text hecate.doc.Text
---@field link string  path relative to the locale root ("reference/"), or an absolute URL

---@class hecate.doc.SidebarItem
---@field text? hecate.doc.Text  defaults to the page title
---@field link? string  page path without extension, relative to the locale root
---@field items? (string|hecate.doc.SidebarItem)[]

---@class hecate.doc.SiteConfiguration
---@field title string  site name; the name of the project is never capitalised (brand kit)
---@field description? hecate.doc.Text
---@field base_path? string  absolute path the site is published under ("/" or "/hecate/"), default "/". It is not used to build the links of the pages, which are relative to the page and open from the file system (OQ-148); it is the path part of the absolute addresses: canonical links, `sitemap.xml`, `llms.txt`, the root redirect and, with `site_origin`, the links of the not-found page
---@field site_origin? string  public origin of the site (scheme, host, port), for the absolute addresses: canonical links, the sitemap, `llms.txt` and the not-found page
---@field default_locale? string  default "en"
---@field locales? hecate.doc.Locale[]  default: the default locale only
---@field top_links? hecate.doc.TopLinkEntry[]  links of the top navigation; default: the top-level sections
---@field sidebar? table<string, (string|hecate.doc.SidebarItem)[]>  explicit sidebar per top-level section
---@field repository_url? string  repository URL, shown as the GitHub link
---@field edit_link_template? string  URL template with `{path}` (path of the source file below the content root)
---@field source_edit_link_template? string  URL template with `{path}` for generated pages (repository path of the source file in their `source` front matter)
---@field footer? hecate.doc.Text
---@field outline_levels? integer[]  heading levels listed in "On this page" (default { 2, 3 })
---@field interface_strings? table<string, table<string, string>>  overrides of the interface strings per locale
---@field logo_path? string|{ light: string, dark?: string }  logo of the project: file(s) of `public/` replacing the brand logo (shown as they are, never recoloured); a string is used for both colour schemes
---@field favicon_path? string|{ light: string, dark?: string }  favicon of the project: file(s) of `public/` (`.svg`, `.png` or `.ico`) replacing the Hecate favicon; with `dark`, each file is announced with a `prefers-color-scheme` media query
---@field sidebar_marker? boolean  draw an accent bar at the left of the current page in the sidebar tree; default false (the current page is then shown by a stronger weight and a tint)
---@field stylesheet_path? string  CSS file (`.css`) of `public/` loaded after the stylesheet of the theme, to override its custom properties: colours (light and dark), highlighting, the three font families, radii, spacing, sidebar width (OQ-38); it may declare its own `@font-face` for font files of `public/`
---@field generate_llms_txt? boolean  write `llms.txt` and `llms-full.txt` (llmstxt.org) for the pages of the default locale; default false
---@field exclude_file_names? string[]  file names left out of the site (default { "README.md" })

local function invalid(field, message)
  error(core.ConfigurationError({
    message = ("doc.config: invalid site configuration `%s`: %s"):format(field, message),
    context = { field = field },
  }), 0)
end

local function check_text(field, value)
  if value == nil or type(value) == "string" then return end
  if type(value) ~= "table" then invalid(field, "expected a string or a table of strings per locale") end
  for code, text in pairs(value) do
    if type(code) ~= "string" or type(text) ~= "string" then
      invalid(field, "expected locale codes mapped to strings")
    end
  end
end

local function check_list(field, value, check_item)
  if type(value) ~= "table" then invalid(field, "expected a list") end
  for index in pairs(value) do
    if math.type(index) ~= "integer" or index < 1 then invalid(field, "expected a list (integer keys from 1)") end
  end
  for index, item in ipairs(value) do check_item(("%s[%d]"):format(field, index), item) end
  if next(value) ~= nil and value[#value] == nil then invalid(field, "expected a list without holes") end
end

local function check_items(field, items)
  check_list(field, items, function(name, item)
    if type(item) == "string" then return end
    if type(item) ~= "table" then invalid(name, "expected a page path or { text, link, items }") end
    check_text(name .. ".text", item.text)
    if item.link ~= nil and type(item.link) ~= "string" then invalid(name .. ".link", "expected a page path") end
    if item.items ~= nil then check_items(name .. ".items", item.items) end
  end)
end

local function check_sidebar(value)
  if type(value) ~= "table" then invalid("sidebar", "expected a table of lists per top-level section") end
  for section, items in pairs(value) do
    if type(section) ~= "string" then invalid("sidebar", "expected section names as keys") end
    check_items("sidebar." .. section, items)
  end
end

local function check_interface_strings(value)
  if type(value) ~= "table" then invalid("interface_strings", "expected a table of interface strings per locale") end
  for code, overrides in pairs(value) do
    if type(code) ~= "string" then invalid("interface_strings", "expected locale codes as keys") end
    local field = "interface_strings." .. code
    if type(overrides) ~= "table" then invalid(field, "expected a table of interface strings") end
    for key, text in pairs(overrides) do
      if type(key) ~= "string" or type(text) ~= "string" then
        invalid(key and (field .. "." .. tostring(key)) or field, "expected a string")
      end
    end
  end
end

-- A public origin: http or https, a host, no whitespace or control characters (RFC 3986, 3.1 and 3.2).
local function check_origin(value)
  if type(value) ~= "string" or value:find("[%c%s\\]") or not value:lower():find("^https?://[^/?#]+") then
    invalid("site_origin", "expected an origin such as https://example.org")
  end
end

-- The path the site is published under, used for absolute addresses only (never for links between pages): absolute, not protocol-relative (RFC 3986, 4.2: a reference starting with
-- `//` is a network-path reference that names another host), made of unreserved characters, sub-delimiters
-- and percent-encodings only.
local function check_base_path(value)
  if type(value) ~= "string" or not value:find("^/") then invalid("base_path", "expected a path starting with /") end
  if value:find("^//") then invalid("base_path", "expected a path starting with a single / (a protocol-relative base names another host)") end
  if value:find("[^%w%-._~!$&'()*+,;=:@/%%]") then
    invalid("base_path", "expected a path without spaces, backslashes, `?`, `#` or control characters")
  end
end

-- A file of `public/`: a relative path of plain segments (no scheme, no `.`, `..` or hidden segment, no
-- backslash, no query). Hidden files are not copied to the site, so naming one could never work.
local function check_public_path(field, value)
  local ok = type(value) == "string" and value ~= "" and not value:find("^/") and not value:find("[%c\\?#:%%]")
    and not value:find("//", 1, true) and not value:find("/$")
  if ok then
    for segment in value:gmatch("[^/]+") do
      if segment:sub(1, 1) == "." then ok = false end
    end
  end
  if not ok then
    invalid(field, "expected the path of a file of public/, relative, without `.`, `..` or hidden segments")
  end
end

-- Media types of the favicon formats a browser accepts in `<link rel="icon">` (HTML Living Standard, 4.6.7.9 and
-- 4.2.6: the `type` attribute is a hint that lets a browser skip a format it does not support).
local FAVICON_TYPES = { svg = "image/svg+xml", png = "image/png", ico = "image/x-icon" }

--- Media type of a favicon file, from its extension; `nil` when the extension is not supported.
---@param path string
---@return string?
function M.favicon_type(path)
  local extension = path:match("%.(%w+)$")
  return extension and FAVICON_TYPES[extension:lower()] or nil
end

local function check_favicon_path(field, value)
  check_public_path(field, value)
  if not M.favicon_type(value) then invalid(field, "expected an .svg, .png or .ico file") end
end

--- The audiences a content tree can be written for (`<guides_dir>/<audience>/`).
M.AUDIENCES = { user = true, maintainer = true }

--- Validates a configuration table and fills in the defaults. Raises
--- `hecate.core.ConfigurationError` (with `context.field`) on the first problem.
---@param raw hecate.doc.SiteConfiguration
---@return hecate.doc.SiteConfiguration
function M.normalise(raw)
  if type(raw) ~= "table" then invalid("site_configuration", "expected a table") end
  -- A key that is not on the list does nothing: an old name (`colors`, `theme`, `logo`) or a typo is refused.
  options.check_site_keys(raw, invalid)
  if type(raw.title) ~= "string" or raw.title == "" then invalid("title", "expected a non-empty string") end
  check_text("description", raw.description)
  check_text("footer", raw.footer)
  if raw.repository_url ~= nil and (type(raw.repository_url) ~= "string" or not html.is_safe_url(raw.repository_url)) then
    invalid("repository_url", "expected a URL with a safe scheme (http, https)")
  end
  if raw.site_origin ~= nil then check_origin(raw.site_origin) end
  if raw.exclude_file_names ~= nil then
    check_list("exclude_file_names", raw.exclude_file_names, function(name, item)
      if type(item) ~= "string" or item == "" or item:find("/", 1, true) then
        invalid(name, "expected a file name without a directory part")
      end
    end)
  end
  if raw.outline_levels ~= nil then
    check_list("outline_levels", raw.outline_levels, function(_, level)
      if math.type(level) ~= "integer" or level < 1 or level > 6 then invalid("outline_levels", "expected heading levels 1 to 6") end
    end)
  end
  local logo
  if raw.logo_path ~= nil then
    if type(raw.logo_path) == "string" then
      check_public_path("logo_path", raw.logo_path)
      logo = { light = raw.logo_path }
    elseif type(raw.logo_path) == "table" then
      check_public_path("logo_path.light", raw.logo_path.light)
      if raw.logo_path.dark ~= nil then check_public_path("logo_path.dark", raw.logo_path.dark) end
      logo = { light = raw.logo_path.light, dark = raw.logo_path.dark }
    else
      invalid("logo_path", "expected a path or { light, dark }")
    end
  end
  local favicon
  if raw.favicon_path ~= nil then
    if type(raw.favicon_path) == "string" then
      check_favicon_path("favicon_path", raw.favicon_path)
      favicon = { light = raw.favicon_path }
    elseif type(raw.favicon_path) == "table" then
      check_favicon_path("favicon_path.light", raw.favicon_path.light)
      if raw.favicon_path.dark ~= nil then check_favicon_path("favicon_path.dark", raw.favicon_path.dark) end
      favicon = { light = raw.favicon_path.light, dark = raw.favicon_path.dark }
    else
      invalid("favicon_path", "expected a path or { light, dark }")
    end
  end
  if raw.sidebar_marker ~= nil and type(raw.sidebar_marker) ~= "boolean" then
    invalid("sidebar_marker", "expected true or false")
  end
  if raw.stylesheet_path ~= nil then
    check_public_path("stylesheet_path", raw.stylesheet_path)
    if not raw.stylesheet_path:lower():find("%.css$") then
      invalid("stylesheet_path", "expected a CSS file (a name ending in .css)")
    end
  end
  if raw.generate_llms_txt ~= nil and type(raw.generate_llms_txt) ~= "boolean" then
    invalid("generate_llms_txt", "expected true or false")
  end
  if raw.sidebar ~= nil then check_sidebar(raw.sidebar) end
  if raw.interface_strings ~= nil then check_interface_strings(raw.interface_strings) end
  for _, key in ipairs({ "edit_link_template", "source_edit_link_template" }) do
    if raw[key] ~= nil and type(raw[key]) ~= "string" then invalid(key, "expected a template containing {path}") end
  end
  if raw.default_locale ~= nil and type(raw.default_locale) ~= "string" then invalid("default_locale", "expected a locale code") end
  if raw.locales ~= nil and type(raw.locales) ~= "table" then invalid("locales", "expected a list of { code, label, lang }") end
  local config = {
    title = raw.title,
    description = raw.description,
    footer = raw.footer,
    site_origin = raw.site_origin and (raw.site_origin:gsub("/+$", "")),
    repository_url = raw.repository_url,
    logo_path = logo,
    favicon_path = favicon,
    sidebar_marker = raw.sidebar_marker == true,
    stylesheet_path = raw.stylesheet_path,
    generate_llms_txt = raw.generate_llms_txt == true,
    edit_link_template = raw.edit_link_template,
    source_edit_link_template = raw.source_edit_link_template,
    sidebar = raw.sidebar or {},
    interface_strings = raw.interface_strings or {},
    exclude_file_names = raw.exclude_file_names or { "README.md" },
    outline_levels = raw.outline_levels or { 2, 3 },
  }
  local base_path = raw.base_path
  if base_path == nil then base_path = "/" end
  check_base_path(base_path)
  ---@cast base_path string
  config.base_path = (base_path:gsub("/*$", "/"))
  config.default_locale = raw.default_locale or "en"
  local locales = raw.locales or { { code = config.default_locale, label = config.default_locale } }
  config.locales = {}
  local seen = {}
  for index, locale in ipairs(locales) do
    if type(locale) ~= "table" or type(locale.code) ~= "string" or not locale.code:find("^[%a][%w%-]*$") then
      invalid("locales[" .. index .. "].code", "expected a code such as \"en\" or \"pt-br\"")
    end
    if seen[locale.code] then invalid("locales[" .. index .. "].code", "duplicate locale " .. locale.code) end
    seen[locale.code] = true
    if locale.label ~= nil and type(locale.label) ~= "string" then invalid("locales[" .. index .. "].label", "expected a string") end
    if locale.lang ~= nil and type(locale.lang) ~= "string" then invalid("locales[" .. index .. "].lang", "expected a BCP 47 tag") end
    config.locales[index] = {
      code = locale.code,
      label = locale.label or locale.code,
      lang = locale.lang or locale.code,
    }
  end
  if not seen[config.default_locale] then
    invalid("default_locale", "the default locale " .. config.default_locale .. " is not in `locales`")
  end
  config.top_links = nil
  if raw.top_links ~= nil then
    if type(raw.top_links) ~= "table" then invalid("top_links", "expected a list of { text, link }") end
    config.top_links = {}
    for index, entry in ipairs(raw.top_links) do
      if type(entry) ~= "table" or type(entry.link) ~= "string" then
        invalid("top_links[" .. index .. "]", "expected { text = ..., link = \"path/\" }")
      end
      if not html.is_safe_url(entry.link) then invalid("top_links[" .. index .. "].link", "unsafe URL scheme") end
      check_text("top_links[" .. index .. "].text", entry.text)
      config.top_links[index] = { text = entry.text, link = entry.link }
    end
  end
  if config.edit_link_template and not config.edit_link_template:find("{path}", 1, true) then
    invalid("edit_link_template", "expected a template containing {path}")
  end
  if config.source_edit_link_template and not config.source_edit_link_template:find("{path}", 1, true) then
    invalid("source_edit_link_template", "expected a template containing {path}")
  end
  return config
end

--- Picks the text for a locale from a string or a per-locale table, falling back to the
--- default locale.
---@param value hecate.doc.Text?
---@param locale string
---@param default_locale string
---@return string?
function M.localise(value, locale, default_locale)
  if type(value) == "table" then return value[locale] or value[default_locale] end
  return value
end

return M
