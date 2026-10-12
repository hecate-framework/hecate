-- Builds the package catalogue table of packages/README.md (pure functions).
local boundaries = require("lib.boundaries")

local M = {}

--- Parses the metadata of a package README.
---@param text string
---@return { summary: string, layer: string, phase: string, status: string, rock: string }?
function M.parse_readme(text)
  local function field(name) return text:match("|%s*" .. name .. "%s*|%s*([^|]-)%s*|") end
  local summary = text:match("\n>%s*([^\n]+)")
  local layer, phase, status = field("Layer"), field("Roadmap phase"), field("Status")
  local rock = (field("Rock") or ""):gsub("`", "")
  if not (summary and layer and phase and status and rock ~= "") then return nil end
  return { summary = summary, layer = layer, phase = phase, status = status:match("^%a[%a ]*%a"):gsub(" —.*$", ""), rock = rock }
end

--- Sorts packages by phase, layer and name (in place).
---@param pkgs { name: string, meta: table }[]
function M.sort(pkgs)
  table.sort(pkgs, function(a, b)
    local pa, pb = tonumber(a.meta.phase) or 99, tonumber(b.meta.phase) or 99
    if pa ~= pb then return pa < pb end
    local ra, rb = boundaries.rank(a.meta.layer) or 99, boundaries.rank(b.meta.layer) or 99
    if ra ~= rb then return ra < rb end
    return a.name < b.name
  end)
end

--- Renders the table (header included) for packages sorted by phase, layer and name.
---@param pkgs { name: string, meta: table }[]
---@return string
function M.render(pkgs)
  M.sort(pkgs)
  local rows = {
    "| Package | Rock | Layer | Phase | Status | Summary |",
    "|---|---|---|---|---|---|",
  }
  for _, p in ipairs(pkgs) do
    local m = p.meta
    rows[#rows + 1] = ("| [`%s`](%s) | `%s` | %s | %s | %s | %s |"):format(p.name, p.name, m.rock, m.layer, m.phase, m.status, m.summary)
  end
  return table.concat(rows, "\n")
end

--- Replaces the first Markdown table of a text with a new one; returns the new text.
---@param text string
---@param table_text string
---@return string
function M.replace_table(text, table_text)
  local first, last
  for line_start, line in text:gmatch("()([^\n]*)\n?") do
    if line:match("^|") then
      first = first or line_start
      last = line_start + #line
    elseif first then
      break
    end
    if line_start > #text then break end
  end
  if not first then return text end
  return text:sub(1, first - 1) .. table_text .. text:sub(last)
end

return M
