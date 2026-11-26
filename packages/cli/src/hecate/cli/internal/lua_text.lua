-- Writing Lua source for generated files (`hecate.lock`, the rockspec and the LuaRocks configuration the CLI generates).
global <const> string

---@class hecate.cli.internal.lua_text
local M = {}

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

--- A Lua string literal for `value`: double quotes, escapes for control characters, the quote and the backslash.
---@param value string
---@return string literal
function M.quote(value)
  return '"' .. value:gsub('[%c"\\]', function(character)
    return ESCAPES[character] or string.format("\\%03d", character:byte())
  end) .. '"'
end

--- A table key: the bare name when it is an identifier, `["..."]` otherwise.
---@param name string
---@return string key
function M.key(name)
  if name:match("^[%a_][%w_]*$") then return name end
  return "[" .. M.quote(name) .. "]"
end

return M
