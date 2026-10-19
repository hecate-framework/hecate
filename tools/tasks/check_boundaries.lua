-- check-boundaries: layer rules (overview.md). Requires match rockspec dependencies, no
-- upward or cyclic dependency, `luv` only in reactor, raw `setmetatable` only in core (and the files of METATABLE_EXEMPT).
local util = require("lib.util")
local b = require("lib.boundaries")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

--- Removes comments and string contents well enough for keyword scanning.
local function code_only(src)
  src = src:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
  return src
end

--- Files outside `core` that may call `setmetatable`, with the reason (OQ-48). A file, not a package, so
--- the exemption stays as narrow as the need.
local METATABLE_EXEMPT = {
  -- JSON markers are metatable tags set on every decoded container, not objects of the class model.
  ["packages/json/src/hecate/json/internal/markers.lua"] = true,
}

return {
  description = "package layering: declared dependencies, no upward/cyclic edge, luv and setmetatable confinement",
  run = function(ctx)
    local problems = {}
    local function add(msg) problems[#problems + 1] = msg end
    local pkgs = ctx.root .. "/packages"
    local rank, graph, declared = {}, {}, {}
    for _, name in ipairs(util.list_dir(pkgs)) do
      local rock = name == "hecate" and "hecate" or "hecate-" .. name
      local spec = read(("%s/%s/%s-scm-1.rockspec"):format(pkgs, name, rock))
      local readme = read(("%s/%s/README.md"):format(pkgs, name)) or ""
      if spec then
        declared[name] = b.rockspec_deps(spec)
        graph[name] = declared[name]
        local label = readme:match("|%s*Layer%s*|%s*([^|]-)%s*|")
        rank[name] = label and b.rank(label)
        if not rank[name] then add(("packages/%s/README.md: missing or unknown Layer"):format(name)) end
      end
    end
    for name, deps in pairs(declared) do
      for _, d in ipairs(deps) do
        if not graph[d] then
          add(("packages/%s: depends on unknown package hecate-%s"):format(name, d))
        elseif rank[name] and rank[d] and rank[d] > rank[name] and name ~= "hecate" then
          add(("packages/%s (layer %d) depends on hecate-%s (layer %d): upward dependency"):format(name, rank[name], d, rank[d]))
        end
      end
    end
    local cycle = b.find_cycle(graph)
    if cycle then add("dependency cycle: " .. table.concat(cycle, " -> ")) end
    for name in pairs(declared) do
      local allowed = { [name] = true }
      for _, d in ipairs(declared[name]) do allowed[d] = true end
      for _, file in ipairs(util.walk(("%s/%s/src"):format(pkgs, name), ".lua")) do
        local src = code_only(read(file) or "")
        local rel = file:sub(#ctx.root + 2)
        for _, p in ipairs(b.required_packages(src)) do
          if not allowed[p] then add(("%s: requires hecate.%s, which is not a declared dependency"):format(rel, p)) end
        end
        if name ~= "reactor" and src:find("require%s*%(?%s*[\"']luv[\"']") then
          add(rel .. ": luv may only be required by hecate.reactor")
        end
        if name ~= "core" and not METATABLE_EXEMPT[rel] and src:find("%f[%w_]setmetatable%s*%(") then
          add(rel .. ": raw setmetatable is reserved to hecate.core (use the object model)")
        end
      end
    end
    table.sort(problems)
    return { ok = #problems == 0, problems = problems }
  end,
}
