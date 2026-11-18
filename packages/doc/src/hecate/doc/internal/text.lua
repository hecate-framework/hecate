-- Text helpers of the generated pages: what comes from a schema, a rockspec or a licence file is data of the project, not
-- Markdown, so it is escaped before it is written into a page.
global <const> require, type, tostring

local M = {}

--- Escapes text for a paragraph or a table cell: one line, no Markdown syntax, no raw HTML, nothing that
--- starts a block at the beginning of the line (CommonMark 0.31.2, 4.1 thematic breaks, 4.3 setext
--- underlines, 5.2 list items) and no character reference (2.5).
---@param text any
---@return string
function M.plain(text)
  text = tostring(text or ""):gsub("%s*[\r\n]+%s*", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("([\\`*_{}%[%]<>|#~&])", "\\%1")
  text = text:gsub("^([%-+=])", "\\%1")
  text = text:gsub("^(%d+)([.)])", "%1\\%2")
  return text
end

--- An inline code span (CommonMark 6.1). In a table cell a pipe is escaped even inside the span
--- (GFM 4.10); elsewhere it is literal.
---@param text any
---@param in_cell? boolean
---@return string
function M.code(text, in_cell)
  text = tostring(text):gsub("%c+", " ")
  if text == "" then return "" end
  local ticks = "`"
  while text:find(ticks, 1, true) do ticks = ticks .. "`" end
  if in_cell then text = text:gsub("|", "\\|") end
  local pad = (text:find("^`") or text:find("`$")) and " " or ""
  return ticks .. pad .. text .. pad .. ticks
end

--- A fenced code block (CommonMark 4.5) that holds `text` as it is: the fence is longer than any run of backticks of
--- the text, so that the text cannot close it.
---@param text string
---@return string
function M.fenced(text)
  local longest = 2
  for run in text:gmatch("`+") do
    if #run > longest then longest = #run end
  end
  local fence = ("`"):rep(longest + 1)
  return fence .. "\n" .. (text:gsub("\n*$", "")) .. "\n" .. fence
end

return M
