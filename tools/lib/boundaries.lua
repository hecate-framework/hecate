-- Layering rules of docs/architecture/overview.md (pure functions).
local M = {}

--- Rank of a layer label as written in package READMEs ("1 — Runtime", "Data", ...).
---@param label string
---@return integer?
function M.rank(label)
  local n = label:match("^(%d)")
  if n then return tonumber(n) end
  local map = { protocol = 2, framework = 3, data = 4, tooling = 5, meta = 6 }
  return map[label:lower():match("^%a+") or ""]
end

--- Package names (without the `hecate-` prefix) listed in rockspec dependencies.
---@param rockspec string
---@return string[]
function M.rockspec_deps(rockspec)
  local deps = {}
  local block = rockspec:match("\ndependencies%s*=%s*(%b{})") or ""
  for name in block:gmatch('"hecate%-([%w_%-]+)') do deps[#deps + 1] = name end
  return deps
end

--- True for a package name: lowercase words (letters and digits) joined by single hyphens (`core`, `unicode-data`).
---@param name string
---@return boolean
function M.valid_name(name)
  return name:match("^[a-z][a-z0-9]*$") ~= nil or name:match("^[a-z][a-z0-9]*%-[a-z0-9%-]*$") ~= nil
    and not name:find("%-%-") and not name:find("%-$")
end

--- The Lua module root of a package: `hecate.<module>`, where a hyphen of the package name becomes an
--- underscore (`unicode-data` is `hecate.unicode_data`, ADR 0032).
---@param name string
---@return string
function M.module_name(name) return (name:gsub("%-", "_")) end

--- Modules `hecate.<pkg>` required by a Lua source; returns package names.
---@param source string
---@return string[]  package names (`unicode_data` is reported as `unicode-data`)
function M.required_packages(source)
  local out = {}
  for name in source:gmatch("require%s*%(?%s*[\"']hecate%.([%w_]+)") do out[#out + 1] = (name:gsub("_", "-")) end
  return out
end

--- Finds a dependency cycle in a graph { name = { dep... } }; returns the cycle path or nil.
---@param graph table<string, string[]>
---@return string[]?
function M.find_cycle(graph)
  local state, stack = {}, {}
  local function visit(n)
    state[n] = 1
    stack[#stack + 1] = n
    for _, d in ipairs(graph[n] or {}) do
      if state[d] == 1 then
        local cycle = { d }
        for i = #stack, 1, -1 do
          table.insert(cycle, 2, stack[i])
          if stack[i] == d then break end
        end
        return cycle
      elseif not state[d] then
        local c = visit(d)
        if c then return c end
      end
    end
    stack[#stack] = nil
    state[n] = 2
  end
  local names = {}
  for n in pairs(graph) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do
    if not state[n] then
      local c = visit(n)
      if c then return c end
    end
  end
end

return M
