-- The theme: page templates, interface strings and static assets (stylesheet, scripts,
-- fonts, brand marks). One theme serves the framework website and user projects (ADR 0012).
global <const> require, package, error, ipairs, table, string

local layout = require("hecate.doc.theme.layout")
local strings = require("hecate.doc.theme.strings")

---@class hecate.doc.Theme
---@field page fun(context: hecate.doc.PageContext): string  renders a page
---@field not_found fun(context: hecate.doc.PageContext): string  renders the 404 page
---@field strings table  interface strings (`for_locale`, `format_date`, `catalogue`)
local M = {
  page = layout.page,
  not_found = layout.not_found,
  strings = strings,
}

--- Static files of the theme, relative to the theme's `assets` directory. They are copied
--- to `assets/` in the built site.
M.asset_files = {
  "theme.css",
  "theme.js",
  "theme-init.js",
  "brand/favicon.svg",
  "brand/hecate-logo-horizontal.svg",
  "brand/hecate-logo-horizontal-on-dark.svg",
  "brand/hecate-mark-compact.svg",
  "brand/hecate-mark-compact-on-dark.svg",
  "brand/pattern-trivium.svg",
  "brand/pattern-trivium-on-dark.svg",
  "brand/LICENSE",
  "fonts/stix-two-text-latin-400-normal.woff2",
  "fonts/stix-two-text-latin-400-italic.woff2",
  "fonts/stix-two-text-latin-600-normal.woff2",
  "fonts/stix-two-text-latin-600-italic.woff2",
  "fonts/fira-sans-latin-400-normal.woff2",
  "fonts/fira-sans-latin-500-normal.woff2",
  "fonts/fira-sans-latin-600-normal.woff2",
  "fonts/fira-code-latin-400-normal.woff2",
  "fonts/fira-code-latin-600-normal.woff2",
  "fonts/OFL-stix-two-text.txt",
  "fonts/OFL-fira-sans.txt",
  "fonts/OFL-fira-code.txt",
}

--- Returns the directory holding the theme's static files, found through the module
--- search path (the files travel with the sources, see OQ-34).
---@return string
function M.assets_directory()
  local file = package.searchpath("hecate.doc.theme", package.path)
  if not file then error("cannot locate the hecate.doc theme on package.path", 2) end
  return (file:gsub("\\", "/"):gsub("/[^/]*$", "")) .. "/assets"
end

return M
