-- Feature modules: validation and initialisation order (http-and-routing.md, "Application and feature modules").
global <const> require, type, error, ipairs, pairs, tostring, table

local core = require("hecate.core")
local errors = require("hecate.kernel.errors")

--- A feature module: one feature's controllers, route modules and services, with the modules it needs. A plain table.
---@class hecate.kernel.FeatureModule
---@field name string  unique, non-empty
---@field requires? string[]  names of the modules that must be initialised before this one
---@field services? fun(container: hecate.container.Container)  binds the services of the feature
---@field routes? (hecate.kernel.RouteModule|table)[]  route modules and controller classes, as for `routing.collect`
---@field filters? hecate.kernel.Filter[]  filters of the feature: they apply only to the routes of this module, after the global filters and before those of a controller and of a route

--- Ordering of feature modules.
---@class hecate.kernel.modules
local modules = {}

local KNOWN = { name = true, requires = true, services = true, routes = true, filters = true }

local function refuse(reason, message, name, extra)
  local context = { reason = reason, module = name }
  if extra then for key, value in pairs(extra) do context[key] = value end end
  error(errors.ModuleError("kernel: " .. message, { context = context }), 0)
end

local function check(module, index)
  if type(module) ~= "table" or type(module.name) ~= "string" or module.name == "" then
    refuse("invalid_module", ("modules[%d] is not a feature module (a table with a non-empty name)"):format(index))
  end
  local name = module.name
  for key in pairs(module) do
    if not KNOWN[key] then refuse("invalid_module", ("module %q: unknown field %q"):format(name, tostring(key)), name) end
  end
  if module.requires ~= nil then
    if type(module.requires) ~= "table" then refuse("invalid_module", ("module %q: requires is a list of names"):format(name), name) end
    for _, required in ipairs(module.requires) do
      if type(required) ~= "string" then refuse("invalid_module", ("module %q: requires lists names"):format(name), name) end
    end
  end
  if module.services ~= nil and type(module.services) ~= "function" then
    refuse("invalid_module", ("module %q: services is a function"):format(name), name)
  end
  for _, field in ipairs({ "routes", "filters" }) do
    if module[field] ~= nil and type(module[field]) ~= "table" then
      refuse("invalid_module", ("module %q: %s is a list"):format(name, field), name)
    end
  end
end

--- Orders `list` so that every module comes after those it requires (depth-first, registration order among
--- independent modules). Raises `hecate.kernel.ModuleError`.
---@param list hecate.kernel.FeatureModule[]
---@return hecate.kernel.FeatureModule[] ordered
function modules.order(list)
  if type(list) ~= "table" then error(core.ArgumentError("kernel.modules.order: list is a list of feature modules"), 2) end
  local by_name = {}
  for index, module in ipairs(list) do
    check(module, index)
    if by_name[module.name] ~= nil then refuse("duplicate_module", ("module %q is registered twice"):format(module.name), module.name) end
    by_name[module.name] = module
  end
  local ordered, state, path = {}, {}, {}
  local function visit(module)
    local mark = state[module.name]
    if mark == "done" then return end
    if mark == "visiting" then
      local cycle, start = {}, 1
      for i, name in ipairs(path) do if name == module.name then start = i end end
      for i = start, #path do cycle[#cycle + 1] = path[i] end
      cycle[#cycle + 1] = module.name
      refuse("dependency_cycle", ("modules depend on each other: %s"):format(table.concat(cycle, " -> ")), module.name, { cycle = cycle })
    end
    state[module.name] = "visiting"
    path[#path + 1] = module.name
    for _, required in ipairs(module.requires or {}) do
      local target = by_name[required]
      if target == nil then
        refuse("missing_dependency", ("module %q requires %q, which is not registered"):format(module.name, required), module.name)
      end
      visit(target)
    end
    path[#path] = nil
    state[module.name] = "done"
    ordered[#ordered + 1] = module
  end
  for _, module in ipairs(list) do visit(module) end
  return ordered
end

return modules
