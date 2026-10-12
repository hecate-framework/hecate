-- Mermaid dependency graph (pure functions).
local M = {}

--- Removes edges implied by other edges (transitive reduction of a DAG).
---@param graph table<string, string[]>
---@return table<string, string[]>
function M.reduce(graph)
  local function reaches(from, target, skip)
    local seen, stack = {}, { from }
    while #stack > 0 do
      local n = table.remove(stack)
      for _, d in ipairs(graph[n] or {}) do
        if not (n == from and d == skip) and not seen[d] then
          if d == target then return true end
          seen[d] = true
          stack[#stack + 1] = d
        end
      end
    end
    return false
  end
  local out = {}
  for name, deps in pairs(graph) do
    out[name] = {}
    for _, d in ipairs(deps) do
      if not reaches(name, d, d) then out[name][#out[name] + 1] = d end
    end
    table.sort(out[name])
  end
  return out
end

--- Renders the Mermaid flowchart.
---@param graph table<string, string[]>
---@param groups { id: string, title: string, members: string[] }[]
---@return string
function M.render(graph, groups)
  local reduced = M.reduce(graph)
  local lines = { "```mermaid", "flowchart TB" }
  for _, g in ipairs(groups) do
    table.sort(g.members)
    lines[#lines + 1] = ("  subgraph %s[%s]"):format(g.id, g.title)
    for _, name in ipairs(g.members) do
      if #reduced[name] == 0 then lines[#lines + 1] = "    " .. name end
      for _, d in ipairs(reduced[name]) do lines[#lines + 1] = ("    %s --> %s"):format(name, d) end
    end
    lines[#lines + 1] = "  end"
  end
  lines[#lines + 1] = "```"
  return table.concat(lines, "\n")
end

return M
