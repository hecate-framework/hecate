-- Markdown renderer: GitHub Flavoured Markdown (CommonMark 0.31 with tables, task lists,
-- strikethrough, autolinks, footnotes and alerts) rendered by comrak through the native module
-- `hecate.doc.native` (ADR 0022), in safe mode: raw HTML is not passed through and unsafe link
-- schemes are dropped. Code fences are highlighted by syntect with the two-face syntaxes.
--
-- Callouts are GFM alerts (`> [!NOTE]`, with an optional title: `> [!NOTE] Title`).
global <const> pcall, require, error

local ok, native = pcall(require, "hecate.doc.native")
if not ok then
  error("the native module hecate.doc.native is not built (run `lua tools/run.lua build-native doc`;"
    .. " it needs a Rust toolchain, or install a prebuilt hecate-doc rock): " .. native, 0)
end

local M = {}

---@class hecate.doc.MarkdownOptions
---@field labels? table<string, string>  titles of the callouts: note, tip, warning, danger, important
---@field resolve_link? fun(href: string): string  rewrites link destinations and image sources
---@field highlight? boolean  highlight fenced code (default true)
---@field strip_title? boolean  remove a leading level-1 heading and return its text as `title`
---@field heading_anchors? boolean  add a permalink to headings (default true)

---@class hecate.doc.Heading
---@field level integer
---@field id string
---@field text string  plain text

---@class hecate.doc.Section
---@field id? string  identifier of the heading that opens the section (nil before the first)
---@field heading? string
---@field level? integer
---@field text string  plain text of the section body

---@class hecate.doc.RenderResult
---@field html string
---@field title? string  set when `strip_title` removed a leading level-1 heading
---@field headings hecate.doc.Heading[]
---@field sections hecate.doc.Section[]
---@field links string[]  every link and image destination met, as written

---@param source string
---@param options? hecate.doc.MarkdownOptions
---@return hecate.doc.RenderResult
function M.render(source, options)
  return native.render(source, options)
end

return M
