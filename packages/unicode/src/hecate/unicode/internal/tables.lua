-- The tables of `hecate-unicode-data`, loaded on first use and expanded into lookups. The layout of the data is
-- checked here: an unknown `format` is refused with a precise error before any table is read (ADR 0032).
global <const> require, error, ipairs, table, tostring

local errors = require("hecate.unicode.errors")

local tables = {}

--- The layouts of `hecate-unicode-data` this version understands.
local SUPPORTED = { 1 }

---@class hecate.unicode.Tables
---@field combining_class table<integer, integer>  canonical combining class of each code point whose class is not 0
---@field decomposition table<integer, integer[]>  fully expanded canonical decomposition (Hangul syllables excluded)
---@field composition table<integer, table<integer, integer>>  primary composites `[first][second]`

--- Validates `data` (the module `hecate.unicode_data`, or a stand-in in tests) and expands its tables.
---@param data { format: any, unicode_version: any, load: fun(name: string): table }
---@return hecate.unicode.Tables
function tables.load(data)
  local known = false
  for _, format in ipairs(SUPPORTED) do known = known or data.format == format end
  if not known then
    error(errors.DataFormatError({
      message = ("hecate-unicode-data has table layout %s (Unicode %s), which this hecate-unicode does not know (it knows %s): install a hecate-unicode-data or a hecate-unicode that match"):format(
        tostring(data.format), tostring(data.unicode_version), table.concat(SUPPORTED, ", ")),
      context = { format = data.format, supported = SUPPORTED, unicode_version = data.unicode_version },
    }), 0)
  end
  local flat = data.load("combining_class")
  local classes = {}
  for i = 1, #flat, 3 do
    local class = flat[i + 2]
    for codepoint = flat[i], flat[i + 1] do classes[codepoint] = class end
  end
  return { combining_class = classes, decomposition = data.load("decomposition"), composition = data.load("composition") }
end

local loaded

--- The tables of the installed data, loaded once.
---@return hecate.unicode.Tables
function tables.get()
  if not loaded then loaded = tables.load(require("hecate.unicode_data")) end
  return loaded
end

return tables
