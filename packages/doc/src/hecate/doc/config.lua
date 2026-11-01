-- Site configuration: validation and defaults for the table returned by `site.lua`.
global <const> require, type, ipairs, pairs, next, error, tostring, table, string, math

local core = require("hecate.core")
local html = require("hecate.doc.internal.html")

--- Validation and defaults of the site configuration.
---@class hecate.doc.config
local M = {}

---@class hecate.doc.Locale
---@field code string  directory name and URL prefix ("en", "fr")
---@field label string  name shown in the locale switch, in that language ("Français")
---@field lang string  BCP 47 tag for the `lang` attribute (defaults to `code`)

---@alias hecate.doc.Text string|table<string, string>  a string, or one string per locale code

---@class hecate.doc.NavLink
---@field text hecate.doc.Text
---@field link string  path relative to the locale root ("reference/"), or an absolute URL

---@class hecate.doc.SidebarItem
---@field text? hecate.doc.Text  defaults to the page title
---@field link? string  page path without extension, relative to the locale root
---@field items? (string|hecate.doc.SidebarItem)[]

---@class hecate.doc.SiteConfig
---@field title string  site name; the name of the project is never capitalised (brand kit)
---@field description? hecate.doc.Text
---@field base? string  URL path the site is served under ("/" or "/hecate/"), default "/"
---@field url? string  public origin, for canonical links and the sitemap
---@field default_locale? string  default "en"
---@field locales? hecate.doc.Locale[]  default: the default locale only
---@field nav? hecate.doc.NavLink[]  top navigation; default: the top-level sections
---@field sidebar? table<string, (string|hecate.doc.SidebarItem)[]>  explicit sidebar per top-level section
---@field repository? string  repository URL, shown as the GitHub link
---@field edit_link? string  pattern with `{path}` (path of the source file below the content root)
---@field source_edit_link? string  pattern with `{path}` for generated pages (repository path of the source file in their `source` front matter)
---@field footer? hecate.doc.Text
---@field outline? integer[]  heading levels listed in "On this page" (default { 2, 3 })
---@field strings? table<string, table<string, string>>  overrides of the interface strings per locale
---@field exclude? string[]  file names left out of the site (default { "README.md" })

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

local function check_strings(value)
  if type(value) ~= "table" then invalid("strings", "expected a table of interface strings per locale") end
  for code, overrides in pairs(value) do
    if type(code) ~= "string" then invalid("strings", "expected locale codes as keys") end
    local field = "strings." .. code
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
    invalid("url", "expected an origin such as https://example.org")
  end
end

-- The path the site is served under: absolute, not protocol-relative (RFC 3986, 4.2: a reference starting with
-- `//` is a network-path reference that names another host), made of unreserved characters, sub-delimiters
-- and percent-encodings only.
local function check_base(value)
  if type(value) ~= "string" or not value:find("^/") then invalid("base", "expected a path starting with /") end
  if value:find("^//") then invalid("base", "expected a path starting with a single / (a protocol-relative base names another host)") end
  if value:find("[^%w%-._~!$&'()*+,;=:@/%%]") then
    invalid("base", "expected a path without spaces, backslashes, `?`, `#` or control characters")
  end
end

--- Validates a configuration table and fills in the defaults. Raises
--- `hecate.core.ConfigurationError` (with `context.field`) on the first problem.
---@param raw hecate.doc.SiteConfig
---@return hecate.doc.SiteConfig
function M.normalise(raw)
  if type(raw) ~= "table" then invalid("config", "expected a table") end
  if type(raw.title) ~= "string" or raw.title == "" then invalid("title", "expected a non-empty string") end
  check_text("description", raw.description)
  check_text("footer", raw.footer)
  if raw.repository ~= nil and (type(raw.repository) ~= "string" or not html.is_safe_url(raw.repository)) then
    invalid("repository", "expected a URL with a safe scheme (http, https)")
  end
  if raw.url ~= nil then check_origin(raw.url) end
  if raw.exclude ~= nil then
    check_list("exclude", raw.exclude, function(name, item)
      if type(item) ~= "string" or item == "" or item:find("/", 1, true) then
        invalid(name, "expected a file name without a directory part")
      end
    end)
  end
  if raw.outline ~= nil then
    check_list("outline", raw.outline, function(_, level)
      if math.type(level) ~= "integer" or level < 1 or level > 6 then invalid("outline", "expected heading levels 1 to 6") end
    end)
  end
  if raw.sidebar ~= nil then check_sidebar(raw.sidebar) end
  if raw.strings ~= nil then check_strings(raw.strings) end
  for _, key in ipairs({ "edit_link", "source_edit_link" }) do
    if raw[key] ~= nil and type(raw[key]) ~= "string" then invalid(key, "expected a pattern containing {path}") end
  end
  if raw.default_locale ~= nil and type(raw.default_locale) ~= "string" then invalid("default_locale", "expected a locale code") end
  if raw.locales ~= nil and type(raw.locales) ~= "table" then invalid("locales", "expected a list of { code, label, lang }") end
  local config = {
    title = raw.title,
    description = raw.description,
    footer = raw.footer,
    url = raw.url and (raw.url:gsub("/+$", "")),
    repository = raw.repository,
    edit_link = raw.edit_link,
    source_edit_link = raw.source_edit_link,
    sidebar = raw.sidebar or {},
    strings = raw.strings or {},
    exclude = raw.exclude or { "README.md" },
    outline = raw.outline or { 2, 3 },
  }
  local base = raw.base
  if base == nil then base = "/" end
  check_base(base)
  ---@cast base string
  config.base = (base:gsub("/*$", "/"))
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
  config.nav = nil
  if raw.nav ~= nil then
    if type(raw.nav) ~= "table" then invalid("nav", "expected a list of { text, link }") end
    config.nav = {}
    for index, entry in ipairs(raw.nav) do
      if type(entry) ~= "table" or type(entry.link) ~= "string" then
        invalid("nav[" .. index .. "]", "expected { text = ..., link = \"path/\" }")
      end
      if not html.is_safe_url(entry.link) then invalid("nav[" .. index .. "].link", "unsafe URL scheme") end
      check_text("nav[" .. index .. "].text", entry.text)
      config.nav[index] = { text = entry.text, link = entry.link }
    end
  end
  if config.edit_link and not config.edit_link:find("{path}", 1, true) then
    invalid("edit_link", "expected a pattern containing {path}")
  end
  if config.source_edit_link and not config.source_edit_link:find("{path}", 1, true) then
    invalid("source_edit_link", "expected a pattern containing {path}")
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
