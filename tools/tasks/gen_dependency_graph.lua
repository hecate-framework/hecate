-- gen-dependency-graph: regenerates the Mermaid graph of docs/architecture/overview.md
-- between the markers <!-- gen-dependency-graph:begin --> and <!-- gen-dependency-graph:end -->.
-- Usage: gen-dependency-graph [--check]
local util = require("lib.util")
local deps = require("lib.deps")
local depgraph = require("lib.depgraph")
local boundaries = require("lib.boundaries")

local BEGIN, END = "<!-- gen-dependency-graph:begin -->", "<!-- gen-dependency-graph:end -->"
local GROUPS = {
  { rank = 0, id = "L0", title = "Layer 0 — Foundation" },
  { rank = 1, id = "L1", title = "Layer 1 — Runtime" },
  { rank = 2, id = "L2", title = "Layer 2 — Protocol" },
  { rank = 3, id = "L3", title = "Layer 3 — Framework" },
  { rank = 4, id = "D", title = "Data" },
  { rank = 5, id = "T", title = "Tooling" },
  { rank = 6, id = "M", title = "Meta" },
}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "regenerate the Mermaid dependency graph in overview.md (--check to verify only)",
  run = function(ctx)
    local graph = deps.graph(ctx.root)
    local groups = {}
    for _, g in ipairs(GROUPS) do groups[g.rank] = { id = g.id, title = g.title, members = {} } end
    for name in pairs(graph) do
      local readme = read(("%s/packages/%s/README.md"):format(ctx.root, name)) or ""
      local rank = boundaries.rank(readme:match("|%s*Layer%s*|%s*([^|]-)%s*|") or "")
      if not rank then return { ok = false, problems = { "packages/" .. name .. "/README.md: unknown Layer" } } end
      table.insert(groups[rank].members, name)
    end
    local ordered = {}
    for _, g in ipairs(GROUPS) do
      if #groups[g.rank].members > 0 then ordered[#ordered + 1] = groups[g.rank] end
    end
    local path = ctx.root .. "/docs/architecture/overview.md"
    local old = read(path) or ""
    local s, e = old:find(BEGIN, 1, true)
    local s2 = old:find(END, 1, true)
    if not (s and s2) then return { ok = false, problems = { "overview.md: markers " .. BEGIN .. " / " .. END .. " not found" } } end
    local new = old:sub(1, e) .. "\n" .. depgraph.render(graph, ordered) .. "\n" .. old:sub(s2)
    local check = false
    for _, a in ipairs(ctx.args) do if a == "--check" then check = true end end
    if new ~= old then
      if check then return { ok = false, problems = { "overview.md graph is out of date; run gen-dependency-graph" } } end
      local f = assert(io.open(path, "wb"))
      f:write(new)
      f:close()
    end
    return { ok = true, problems = {} }
  end,
}
