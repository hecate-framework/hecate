-- Site configuration: validation and defaults for the table returned by `site.lua`.
global <const> require, type, ipairs, pairs, error, tostring, table, string

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
  local base = raw.base or "/"
  if type(base) ~= "string" or not base:find("^/") then invalid("base", "expected a path starting with /") end
  config.base = base:gsub("/*$", "/")
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
  for _, level in ipairs(config.outline) do
    if type(level) ~= "number" or level < 1 or level > 6 then invalid("outline", "expected heading levels 1 to 6") end
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
