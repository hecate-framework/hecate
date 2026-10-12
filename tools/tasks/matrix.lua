-- matrix: the CI matrix as JSON. Usage: matrix [--packages a,b,c] (default: all packages).
local util = require("lib.util")
local deps = require("lib.deps")

local PLATFORMS = { "ubuntu-latest", "macos-latest", "windows-latest" }

return {
  description = "CI matrix (platforms x packages) as JSON (--packages a,b to restrict)",
  run = function(ctx)
    local names = {}
    local graph = deps.graph(ctx.root)
    local chosen
    for i, a in ipairs(ctx.args) do
      if a == "--packages" and ctx.args[i + 1] then
        chosen = {}
        for p in ctx.args[i + 1]:gmatch("[^,]+") do chosen[p] = true end
      end
    end
    for name in pairs(graph) do
      if not chosen or chosen[name] then names[#names + 1] = name end
    end
    table.sort(names)
    local include = {}
    for _, os_name in ipairs(PLATFORMS) do
      for _, pkg in ipairs(names) do include[#include + 1] = { os = os_name, package = pkg } end
    end
    return { ok = true, problems = {}, data = { include = include }, output = util.json({ include = include }) }
  end,
}
