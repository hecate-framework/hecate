-- A page of the site in one locale: its source, metadata and rendered body.
global <const> require, pairs

local core = require("hecate.core")

---@class hecate.doc.Page
---@field locale string  locale the page is built for
---@field id string  path without extension, relative to the locale root ("guide/concurrency")
---@field url string  URL path, including the base path ("/en/guide/concurrency/")
---@field title string
---@field description? string
---@field meta table<string, any>  front matter
---@field html string  rendered body (without the leading title heading)
---@field headings hecate.doc.Heading[]
---@field sections hecate.doc.Section[]
---@field fallback boolean  true when the content is the default locale's, shown in this locale
---@field source_locale string  locale of the file the content comes from
---@field source_path string  path of the source file, as given to the file system
---@field relative_path string  source file relative to the content root ("en/guide/concurrency.md")
---@field order? number
---@field layout "doc"|"home"
---@overload fun(fields: table): hecate.doc.Page
local Page = core.class("Page")

--- Creates a page from its fields.
---@param fields table
function Page:init(fields)
  for key, value in pairs(fields) do self[key] = value end
end

return core.finalise(Page)
