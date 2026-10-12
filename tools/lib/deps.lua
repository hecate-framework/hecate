-- Reads the package dependency graph from the rockspecs.
local util = require("lib.util")
local boundaries = require("lib.boundaries")

local M = {}

---@param root string
---@return table<string, string[]> package -> direct hecate dependencies
function M.graph(root)
  local graph = {}
  for _, name in ipairs(util.list_dir(root .. "/packages")) do
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
