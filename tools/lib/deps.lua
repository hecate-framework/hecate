-- Reads the package dependency graph from the rockspecs.
local boundaries = require("lib.boundaries")
local package_kind = require("lib.package_kind")

local M = {}

---@param root string
---@return table<string, string[]> package -> direct hecate dependencies
function M.graph(root)
  local graph = {}
  -- Only the rocks: a package of another kind (`actions`) has no rockspec and is no node of the graph.
  for _, name in ipairs(package_kind.rocks(root)) do
    local rock = name == "hecate" and "hecate" or "hecate-" .. name
    local f = io.open(("%s/packages/%s/%s-scm-1.rockspec"):format(root, name, rock), "rb")
    if f then
      graph[name] = boundaries.rockspec_deps(f:read("a"))
      f:close()
    end
  end
  return graph
end

return M
