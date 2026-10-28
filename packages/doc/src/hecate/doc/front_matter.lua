-- Front matter: a block of `key: value` lines between two `---` lines at the very start
-- of a page. This is the flat subset of YAML 1.2 that pages need: scalars (plain, single
-- or double quoted, integers, booleans), inline lists (`[a, "b"]`) and block lists
-- (`key:` followed by `- item` lines). Nested mappings are not supported.
global <const> string, table, tonumber, require, type, error, ipairs, pairs, next

local errors = require("hecate.doc.errors")

--- Parser of the front matter of a Markdown page.
---@class hecate.doc.front_matter
local M = {}

local function fail(message, path, line)
  error(errors.BuildError({
    message = ("doc.front_matter.parse: invalid front matter%s: %s"):format(line and (" at line " .. line) or "", message),
    context = { path = path, line = line },
  }), 0)
end

local ESCAPES = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }

local function parse_scalar(text, path, line)
  local quoted = text:match('^"(.*)"$')
  if quoted then
    if quoted:find('[^\\]"') or quoted:find('^"') then fail("unescaped quote in " .. text, path, line) end
    return (quoted:gsub("\\(.)", function(char) return ESCAPES[char] or ("\\" .. char) end))
  end
  quoted = text:match("^'(.*)'$")
  if quoted then return (quoted:gsub("''", "'")) end
  if text == "true" then return true end
  if text == "false" then return false end
  if text:match("^%-?%d+$") then return tonumber(text) end
  if text:find('^["\']') then fail("unterminated string " .. text, path, line) end
  return (text:gsub("%s+#.*$", ""))
end

local function split_list(inside)
  local items, current, quote = {}, {}, nil
  for char in inside:gmatch(".") do
    if quote then
      current[#current + 1] = char
      if char == quote then quote = nil end
    elseif char == '"' or char == "'" then
      quote = char
      current[#current + 1] = char
    elseif char == "," then
      items[#items + 1] = table.concat(current)
      current = {}
    else
      current[#current + 1] = char
    end
  end
  items[#items + 1] = table.concat(current)
  return items
end

--- Splits a page into its front matter and its body. Returns the metadata table (empty
--- when the page has no front matter) and the body text. A page without a closing `---`
--- line, a malformed line or a duplicate key raises `hecate.doc.BuildError`.
---@param source string  page text; `\r\n` and a byte order mark are accepted
---@param path? string  used in error context
---@return table<string, any> meta
---@return string body
function M.parse(source, path)
  source = source:gsub("^\xEF\xBB\xBF", ""):gsub("\r\n", "\n")
  if not source:find("^%-%-%-[ \t]*\n") then return {}, source end
  local lines, body_start = {}, nil
  local line_number = 1
  local position = source:find("\n", 1, true) + 1
  while position <= #source + 1 do
    local newline = source:find("\n", position, true)
    local line = source:sub(position, (newline or #source + 1) - 1)
    line_number = line_number + 1
    if line:match("^%-%-%-[ \t]*$") or line:match("^%.%.%.[ \t]*$") then
      body_start = newline and newline + 1 or #source + 1
      break
    end
    lines[#lines + 1] = { text = line, number = line_number }
    if not newline then break end
    position = newline + 1
  end
  if not body_start then
    error(errors.BuildError({
      message = "doc.front_matter.parse: invalid front matter at line 1: missing closing `---` line", context = { path = path, line = 1 },
    }), 0)
  end
  local meta, list_key = {}, nil
  for _, entry in ipairs(lines) do
    local text, number = entry.text, entry.number
    if text:match("^%s*$") or text:match("^%s*#") then
      -- blank line or comment
    elseif list_key and text:match("^%s*%-%s") then
      local list = meta[list_key]
      list[#list + 1] = parse_scalar(text:match("^%s*%-%s+(.-)%s*$"), path, number)
    else
      local key, value = text:match("^([%w_%-]+):%s*(.-)%s*$")
      if not key then fail("expected `key: value`, got `" .. text .. "`", path, number) end
      if meta[key] ~= nil then fail("duplicate key `" .. key .. "`", path, number) end
      list_key = nil
      if value == "" then
        meta[key] = {}
        list_key = key
      elseif value:match("^%[.*%]$") then
        local items = {}
        local inside = value:sub(2, -2)
        if inside:match("%S") then
          for _, item in ipairs(split_list(inside)) do
            items[#items + 1] = parse_scalar(item:match("^%s*(.-)%s*$"), path, number)
          end
        end
        meta[key] = items
      else
        meta[key] = parse_scalar(value, path, number)
      end
    end
  end
  for key, value in pairs(meta) do
    if type(value) == "table" and #value == 0 and next(value) == nil then meta[key] = "" end
  end
  return meta, source:sub(body_start)
end

return M
