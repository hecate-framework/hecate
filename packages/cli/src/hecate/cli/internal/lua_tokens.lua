-- A tokenizer for the Lua source of a manifest, just precise enough to find tables and entries without being fooled
-- by strings, comments and long brackets. It does not parse Lua: it only splits it, with byte positions.
global <const> load, string, ipairs, pcall, select, type

---@class hecate.cli.Token
---@field kind "name"|"string"|"number"|"symbol"|"comment"
---@field text string  the source text of the token
---@field start integer  first byte
---@field stop integer  last byte
---@field value? string  the content of a string token

---@class hecate.cli.internal.lua_tokens
local M = {}

--- The level of the long bracket that starts at `position` (`[[` is 0, `[==[` is 2), nil when there is none.
local function long_bracket_level(source, position)
  local equals = source:match("^%[(=*)%[", position)
  return equals and #equals or nil
end

--- The end of the long bracket of `level` that starts at `position`: the byte after its closing bracket, nil when it
--- is never closed.
local function long_bracket_end(source, position, level)
  local _, stop = source:find("]" .. string.rep("=", level) .. "]", position + level + 2, true)
  return stop
end

local ESCAPED = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

--- The content of a short string literal: the text between the quotes, with the usual escapes read.
local function short_string_value(literal)
  local inner = literal:sub(2, -2)
  if not inner:find("\\", 1, true) then return inner end
  local chunk = load("return " .. literal, "=string", "t", {})
  local ok, value = false, nil
  if chunk then ok, value = pcall(chunk) end
  if ok and type(value) == "string" then return value end
  return (inner:gsub("\\(.)", function(character) return ESCAPED[character] or character end))
end

--- Splits `source` into tokens, comments included (`kind = "comment"`). Returns nil and a message when a string, long
--- bracket or block comment is never closed.
---@param source string
---@return hecate.cli.Token[]? tokens
---@return string? err
function M.tokenize(source)
  local tokens, position, length = {}, 1, #source
  local function add(kind, start, stop, value)
    tokens[#tokens + 1] = { kind = kind, text = source:sub(start, stop), start = start, stop = stop, value = value }
  end
  while position <= length do
    local character = source:sub(position, position)
    if character:match("%s") then
      position = position + 1
    elseif source:sub(position, position + 1) == "--" then
      local level = long_bracket_level(source, position + 2)
      if level then
        local stop = long_bracket_end(source, position + 2, level)
        if not stop then return nil, "a block comment is never closed" end
        add("comment", position, stop)
        position = stop + 1
      else
        local stop = (source:find("\n", position, true) or length + 1) - 1
        add("comment", position, stop)
        position = stop + 1
      end
    elseif character == '"' or character == "'" then
      local cursor = position + 1
      while true do
        local current = source:sub(cursor, cursor)
        if current == "" or current == "\n" then return nil, "a string is never closed" end
        if current == "\\" then cursor = cursor + 2
        elseif current == character then break
        else cursor = cursor + 1 end
      end
      add("string", position, cursor, short_string_value(source:sub(position, cursor)))
      position = cursor + 1
    elseif character == "[" and long_bracket_level(source, position) then
      local level = long_bracket_level(source, position) --[[@as integer]]
      local stop = long_bracket_end(source, position, level)
      if not stop then return nil, "a long string is never closed" end
      add("string", position, stop, source:sub(position + level + 2, stop - level - 2))
      position = stop + 1
    elseif character:match("[%a_]") then
      local stop = select(2, source:find("^[%w_]*", position + 1)) --[[@as integer]]
      add("name", position, stop)
      position = stop + 1
    elseif character:match("%d") then
      local stop = select(2, source:find("^[%w%.]*", position + 1)) --[[@as integer]]
      add("number", position, stop)
      position = stop + 1
    else
      add("symbol", position, position)
      position = position + 1
    end
  end
  return tokens
end

--- The tokens without the comments.
---@param tokens hecate.cli.Token[]
---@return hecate.cli.Token[] significant
function M.significant(tokens)
  local list = {}
  for _, token in ipairs(tokens) do
    if token.kind ~= "comment" then list[#list + 1] = token end
  end
  return list
end

return M
