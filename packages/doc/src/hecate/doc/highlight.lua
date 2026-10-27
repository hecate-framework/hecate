-- Syntax highlighting of code: syntect with the two-face syntax set through the native module
-- `hecate.doc.native` (ADR 0022). The output only ever contains `<span class="hl-...">` elements
-- around escaped text; the stylesheet maps the scope classes to the brand tokens.
global <const> require, pcall, error

local html = require("hecate.doc.internal.html")

local ok, native = pcall(require, "hecate.doc.native")
if not ok then
  error("the native module hecate.doc.native is not built (run `lua tools/run.lua build-native doc`): " .. native, 0)
end

--- Syntax highlighting of code blocks (native module).
---@class hecate.doc.highlight
local M = {}

--- Returns true when a syntax exists for the language (a name or a file extension).
---@param language string
---@return boolean
function M.supports(language) return native.highlight("", language) ~= nil end

--- Highlights `code`. The result is escaped HTML, safe to place inside `<code>`; the code of
--- an unknown language is escaped and left plain.
---@param language string  language name from the info string ("" for none)
---@param code string
---@return string html
function M.render(language, code)
  return native.highlight(code, language) or html.escape(code)
end

return M
