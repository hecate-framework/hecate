-- Markdown renderer: GitHub Flavoured Markdown (CommonMark 0.31 with tables, task lists,
-- strikethrough, autolinks, footnotes and alerts) rendered by comrak through the native module
-- `hecate.doc.native` (ADR 0022), in safe mode: raw HTML is not passed through and unsafe link
-- schemes are dropped. Code fences are highlighted by syntect with the two-face syntaxes.
--
-- Callouts are GFM alerts (`> [!NOTE]`, with an optional title: `> [!NOTE] Title`).
global <const> pcall, require, error, type, tostring

local ok, native = pcall(require, "hecate.doc.native")
if not ok then
  error("the native module hecate.doc.native is not built (run `lua tools/run.lua build-native doc`;"
    .. " it needs a Rust toolchain, or install a prebuilt hecate-doc rock): " .. native, 0)
end

local core = require("hecate.core")

--- Opening of the code block that the native renderer writes for a fence whose info string is `mermaid`. Text
--- inside code is escaped and raw HTML is not passed through, so only a real fence produces it.
local DIAGRAM_BLOCK = "<div class=\"code-block\" data-language=\"mermaid\">"

--- Markdown renderer (native module).
---@class hecate.doc.markdown
local M = {}

--- Largest source, in bytes, that `render` accepts (the limit of the native module).
---@type integer
M.MAX_INPUT_BYTES = native.MAX_INPUT_BYTES
--- Largest number of block containers (quotes and list items) that one line may open.
---@type integer
M.MAX_NESTING = native.MAX_NESTING
--- Largest HTML a render may produce, in bytes.
---@type integer
M.MAX_OUTPUT_BYTES = native.MAX_OUTPUT_BYTES
--- The HTML may be at most this many times the source (and at least 1 MiB).
---@type integer
M.MAX_OUTPUT_RATIO = native.MAX_OUTPUT_RATIO

---@class hecate.doc.MarkdownOptions
---@field labels? table<string, string>  titles of the callouts: note, tip, warning, danger (the title of a CAUTION alert), important
---@field resolve_link? fun(href: string): string  rewrites link destinations and image sources
---@field highlight? boolean  highlight fenced code (default true)
---@field strip_title? boolean  remove a leading level-1 heading and return its text as `title`
---@field heading_anchors? boolean  add a permalink to headings (default true)
---@field file? string  name of the source, quoted in the messages of a refusal

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
---@field diagrams boolean  the body holds a fenced block with the info string `mermaid` (ADR 0033)

--- Renders GitHub Flavoured Markdown to HTML in safe mode. Raises `hecate.core.ArgumentError` when `source` is
--- not a valid UTF-8 string (the message gives the byte position), when it is larger than `M.MAX_INPUT_BYTES`
--- (8 MiB), when a line opens more than `M.MAX_NESTING` (100) block containers (quotes and list items; a nesting
--- limit far above real documentation that bounds the work of the renderer), or when the HTML would exceed the
--- output limit (`M.MAX_OUTPUT_RATIO` times the source, between 1 MiB and `M.MAX_OUTPUT_BYTES`). The page reader
--- reports them as a `hecate.doc.BuildError` naming the file.
---@param source string
---@param options? hecate.doc.MarkdownOptions
---@return hecate.doc.RenderResult
function M.render(source, options)
  local where = options and options.file and (" (" .. tostring(options.file) .. ")") or ""
  if type(source) ~= "string" then
    error(core.ArgumentError("doc.markdown.render: expects a string" .. where), 2)
  end
  if #source > M.MAX_INPUT_BYTES then
    error(core.ArgumentError(("doc.markdown.render: the markdown is %d bytes, more than the limit of %d bytes"
      .. " (MAX_INPUT_BYTES, 8 MiB)%s"):format(#source, M.MAX_INPUT_BYTES, where)), 2)
  end
  local result, refusal = native.render(source, options)
  if result == nil then
    error(core.ArgumentError("doc.markdown.render: " .. refusal .. where), 2)
  end
  result.diagrams = result.html:find(DIAGRAM_BLOCK, 1, true) ~= nil
  -- A table scrolls horizontally inside its own wrapper instead of overflowing the content column. Text is
  -- escaped and raw HTML is not passed through, so these tags only come from real tables. The theme script
  -- makes a wrapper that actually scrolls focusable (keyboard access, WCAG 2.1 SC 2.1.1).
  result.html = result.html:gsub("<table>", "<div class=\"table-wrap\"><table>"):gsub("</table>", "</table></div>")
  return result
end

return M
