-- Internal Markdown link checking (pure functions; file access is injected).
local M = {}

--- GitHub-style heading slug.
---@param heading string
---@return string
function M.slug(heading)
  local s = heading:lower():gsub("`", ""):gsub("[^%w%s_%-]", ""):gsub("%s", "-")
  return s
end

--- Returns the set of anchors defined by the headings of a Markdown text (a trailing `{#id}`
--- sets the identifier, as in hecate.doc).
---@param text string
---@return table<string, boolean>
function M.anchors(text)
  local set, seen, fenced = {}, {}, false
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("^%s*```") or line:match("^%s*~~~") then fenced = not fenced
    elseif not fenced then
      local h = line:match("^#+%s+(.-)%s*#*%s*$")
      local custom = h and h:match("{#([%w_%-%.:]+)}%s*$")
      if custom then
        -- `## Title {#id}`: the explicit identifier of hecate.doc (a heading of the generated reference).
        set[custom] = true
      elseif h then
        local base = M.slug((h:gsub("%[([^%]]*)%]%([^)]*%)", "%1")))
        local n = seen[base] or 0
        seen[base] = n + 1
        set[n == 0 and base or (base .. "-" .. n)] = true
      end
    end
  end
  return set
end

--- Extracts internal link targets (path, fragment, line) from a Markdown text.
---@param text string
---@return { path: string, fragment: string?, line: integer }[]
function M.extract(text)
  local links, fenced, n = {}, false, 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    if line:match("^%s*```") or line:match("^%s*~~~") then fenced = not fenced
    elseif not fenced then
      local stripped = line:gsub("`[^`]*`", "")
      for target in stripped:gmatch("%]%(([^)%s]+)[^)]*%)") do
        if not target:match("^%a[%w+.-]*:") and not target:match("^//") then
          local path, frag = target:match("^([^#]*)#?(.*)$")
          links[#links + 1] = { path = path, fragment = frag ~= "" and frag or nil, line = n }
        end
      end
    end
  end
  return links
end

return M
