-- Affected-package computation (pure functions).
local M = {}

--- Builds the set of packages affected by changed files, following reverse dependencies.
---@param files string[]  repository-relative changed paths
---@param deps table<string, string[]>  package -> direct dependencies
---@return string[] sorted affected package names
function M.compute(files, deps)
  local affected, all = {}, false
  for _, file in ipairs(files) do
    local pkg = file:match("^packages/([^/]+)/")
    if pkg then
      if deps[pkg] then affected[pkg] = true end
    elseif not (file:match("^docs/") or file:match("%.md$") or file:match("^website/")
        or file:match("^%.claude/") or file:match("^examples/")) then
      all = true
    end
  end
  local reverse = {}
  for name, list in pairs(deps) do
    for _, d in ipairs(list) do
      reverse[d] = reverse[d] or {}
      table.insert(reverse[d], name)
    end
  end
  local queue = {}
  for name in pairs(all and deps or affected) do
    affected[name] = true
    queue[#queue + 1] = name
  end
  while #queue > 0 do
    local n = table.remove(queue)
    for _, r in ipairs(reverse[n] or {}) do
      if not affected[r] then
        affected[r] = true
        queue[#queue + 1] = r
      end
    end
  end
  local out = {}
  for name in pairs(affected) do out[#out + 1] = name end
  table.sort(out)
  return out
end

return M
