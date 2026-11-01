-- Translates a byte offset in a text into the line and column reported by `DecodeError`, so that
-- the native modules report the offset only and the positions are computed once, in one place.
global <const> math, string

local find, sub, gsub = string.find, string.sub, string.gsub

local M = {}

--- Locates a byte offset: the 1-based line (a line ends at a line feed) and the 1-based column,
--- counted in characters (UTF-8 code points) before the offset on that line.
---@param text string
---@param offset integer  number of bytes before the offending byte, 0 to `#text`
---@return integer line
---@return integer column
function M.locate(text, offset)
  offset = math.max(0, math.min(offset, #text))
  local line, line_start = 1, 1
  local from = 1
  while true do
    local at = find(text, "\n", from, true)
    if at == nil or at > offset then break end
    line = line + 1
    line_start = at + 1
    from = at + 1
  end
  local before = sub(text, line_start, offset)
  local _, continuation = gsub(before, "[\128-\191]", "")
  return line, #before - continuation + 1
end

return M
