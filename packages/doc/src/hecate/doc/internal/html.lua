-- HTML helpers shared by the Markdown renderer, the theme and the search index.
-- Escaping is the default everywhere: text and attribute values are escaped here, and
-- URLs are filtered by scheme (an allow-list), so content can never inject markup or a
-- script URL (OWASP "XSS prevention", output encoding; WHATWG HTML 13.1.2.3).
global <const> string, table, pairs, ipairs, tostring, tonumber, utf8

local M = {}

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

--- Escapes text for use as element content or as a double-quoted attribute value.
---@param value any
---@return string
function M.escape(value) return (tostring(value):gsub("[&<>\"']", ESCAPES)) end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = "\u{A0}" }

--- Decodes the entities produced by `escape` (and numeric references).
---@param text string
---@return string
function M.unescape(text)
  return (text:gsub("&(#?)(%w+);", function(hash, name)
    if hash == "#" then
      local code = name:match("^[xX](%x+)$")
      code = code and tonumber(code, 16) or tonumber(name)
      if code and code > 0 and code <= 0x10FFFF and not (code >= 0xD800 and code <= 0xDFFF) then
        return utf8.char(code)
      end
      return nil
    end
    return ENTITIES[name]
  end))
end

--- Removes tags from rendered HTML and decodes entities, giving plain text. Each tag is
--- replaced by `separator` (a space by default, so block elements do not run together; use
--- "" for inline content).
---@param html string
---@param separator? string
---@return string
function M.strip_tags(html, separator)
  local text = html:gsub("<[^>]*>", separator or " ")
  return (M.unescape(text))
end

local SAFE_SCHEMES = { http = true, https = true, mailto = true, tel = true, ftp = true }

--- Returns true when a URL is safe to put in `href` or `src`: relative, or with an
--- allow-listed scheme. `javascript:`, `data:`, `vbscript:` and unknown schemes are not.
---@param url string
---@return boolean
function M.is_safe_url(url)
  -- Browsers ignore ASCII whitespace and control characters inside the scheme.
  local compact = url:gsub("[%c%s]", ""):lower()
  local scheme = compact:match("^([%a][%w+.%-]*):")
  if scheme == nil then return true end
  return SAFE_SCHEMES[scheme] == true
end

--- Folds the upper-case letters of Basic Latin and of Latin-1 Supplement (UTF-8) to lower
--- case; other characters are kept.
---@param text string
---@return string
function M.lower(text)
  text = text:lower()
  return (text:gsub("\xC3([\x80-\x9E])", function(byte)
    if byte == "\x97" then return nil end -- multiplication sign
    return "\xC3" .. string.char(byte:byte() + 32)
  end))
end

--- Builds a heading identifier: lower case, spaces become hyphens, ASCII punctuation is
--- dropped, non-ASCII letters are kept.
---@param text string
---@return string
function M.slug(text)
  local slug = M.lower(text)
  slug = slug:gsub("%c", ""):gsub("%s+", "-")
  slug = slug:gsub("%p", function(char) return (char == "-" or char == "_") and char or "" end)
  slug = slug:gsub("%-+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "section" end
  return slug
end

--- Joins the key/value pairs of a table into an attribute string (sorted, escaped);
--- `true` renders a bare attribute and `false` or `nil` omit it.
---@param attributes table<string, string|boolean|number>
---@return string
function M.attributes(attributes)
  local names = {}
  for name in pairs(attributes) do names[#names + 1] = name end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    local value = attributes[name]
    if value == true then
      out[#out + 1] = " " .. name
    elseif value ~= false and value ~= nil then
      out[#out + 1] = (" %s=\"%s\""):format(name, M.escape(value))
    end
  end
  return table.concat(out)
end

return M
