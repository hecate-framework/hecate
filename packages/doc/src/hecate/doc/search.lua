-- Search index: one document per page section (the part of a page under a heading of
-- level 2 or 3, or before the first one), serialised as JSON and queried in the browser
-- by `theme.js`. No stemming and no server: the client folds case and diacritics and
-- matches word prefixes, which suits documentation and French text alike.
global <const> require, ipairs, table, string, utf8

local json = require("hecate.json")

--- Builder of the client-side search index.
---@class hecate.doc.search
local M = {}

--- Version of the index format, so `theme.js` can reject an index it does not know.
M.FORMAT_VERSION = 1

--- Longest text kept per section, in bytes (the index would otherwise duplicate the
--- whole site; the first part of a section is what a reader recognises).
M.MAX_TEXT = 2400

---@class hecate.doc.SearchPage
---@field title string
---@field url string  URL of the page
---@field category? string  name of the section the page belongs to, shown in results
---@field sections hecate.doc.Section[]

--- Cuts text to at most `limit` bytes without splitting a UTF-8 sequence.
---@param text string
---@param limit integer
---@return string
function M.truncate(text, limit)
  if #text <= limit then return text end
  local cut = limit
  while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
    cut = cut - 1
  end
  return text:sub(1, cut)
end

--- Builds the index of one locale. Documents keep the order of `pages`.
---@param locale string
---@param pages hecate.doc.SearchPage[]
---@return table
function M.build(locale, pages)
  local documents = {}
  for _, page in ipairs(pages) do
    for _, section in ipairs(page.sections) do
      local text = M.truncate(section.text, M.MAX_TEXT)
      if section.id or text ~= "" then
        documents[#documents + 1] = {
          t = page.title,
          h = section.heading,
          c = page.category,
          u = section.id and (page.url .. "#" .. section.id) or page.url,
          x = text,
        }
      end
    end
  end
  return { version = M.FORMAT_VERSION, locale = locale, documents = documents }
end

--- Serialises an index (`build` result) to JSON.
---@param index table
---@return string
function M.encode(index)
  -- `<`, `>` and `&` are written as escapes, so the text can also sit inside a `<script>` element.
  local text = json.encode(index, { canonical = true }):gsub("[<>&]", function(char)
    return ("\\u%04x"):format(char:byte())
  end)
  return text
end

return M
