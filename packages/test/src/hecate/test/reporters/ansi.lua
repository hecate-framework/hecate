-- The only place that knows terminal escape sequences (ECMA-48 control sequences, "SGR" and "EL"):
-- every other part of the reporters asks this module to paint or to erase.
global <const> type

---@class hecate.test.ansi
local M = {}

local ESC = "\27["

-- Select Graphic Rendition parameters; orange is the 256-colour palette entry 208 (ISO 8613-6).
local CODES = { green = "32", red = "31", orange = "38;5;208", bold = "1" }

--- Wraps `text` in the escape sequences of `color` when `enabled`; returns it unchanged otherwise.
---@param text string
---@param color "green"|"red"|"orange"|"bold"
---@param enabled boolean
---@return string
function M.paint(text, color, enabled)
  if not enabled then return text end
  return ESC .. CODES[color] .. "m" .. text .. ESC .. "0m"
end

--- Returns to the start of the line and erases it (carriage return, then Erase in Line, `CSI 2 K`).
M.REDRAW = "\r" .. ESC .. "2K"

return M
