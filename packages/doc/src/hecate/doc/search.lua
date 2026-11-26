-- Search index: one document per page section (the part of a page under a heading of
-- level 2 or 3, or before the first one), written as a script file that registers the index
-- and queried in the browser by `theme.js`. A script loads from the file system (file://)
-- and from any static host; a `fetch` of a JSON file does not load from file://. No stemming and no server: the client folds case and diacritics and
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
---@field url string  path of the page file below the root of the site (percent-encoded, relative to the root, never starting with `/`), such as `en/guide/index.html`; `theme.js` prefixes the path from the page to the root
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

--- Serialises a string to a JSON string literal, which is also a JavaScript string literal (ES2019 and later).
---@param text string
---@return string
function M.encode_string(text)
  return (json.encode(text):gsub("[<>&]", function(char) return ("\\u%04x"):format(char:byte()) end))
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

--- Name of the global registry the script of an index writes to (read by `theme.js`).
M.REGISTRY = "hecateDocSearchIndex"

--- Serialises an index as the content of a script file (`assets/search-<locale>.js`): it assigns the index to
--- `window.hecateDocSearchIndex[<locale>]`. The text is a function of the index only (no timestamp).
---@param index table  a `build` result
---@return string
function M.script(index)
  local locale = M.encode_string(index.locale)
  return ("(window.%s = window.%s || {})[%s] = %s;\n"):format(M.REGISTRY, M.REGISTRY, locale, M.encode(index))
end

return M
