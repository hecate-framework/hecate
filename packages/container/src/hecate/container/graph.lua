-- Boot validation of a binding graph (container.md, "Boot validation"). Nothing is constructed here.
-- Fowler (2004), "Forms of Dependency Injection": the dependencies are declared, so the whole graph can be checked
-- before the first resolution; Seemann (2011), section 3.2 "Composition Root": it is composed, and so checked, in
-- one place. The lifetime rule is the "captive dependency" of Seemann.
global <const> require, ipairs, table, type

local core = require("hecate.core")
local errors = require("hecate.container.errors")
local Lifetime = require("hecate.container.lifetime")

---@class hecate.container.graph
local graph = {}

--- A key as a diagnostic shows it: a name as it is, an interface by its `core.name`, never by address.
---@param key string|table
---@return string
function graph.render(key)
  if type(key) == "string" then return key end
  return core.name(key)
end

local function render_path(path)
  local out = {}
  for i, key in ipairs(path) do out[i] = graph.render(key) end
  return out
end

local function copy(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

--- The binding record the container stores.
---@class hecate.container.Binding
---@field key string|table
---@field definition table|function  a finalised class or a factory
---@field lifetime hecate.core.EnumerationValue
---@field requires (string|table)[]
---@field needs_scope? boolean  set by `annotate`: constructing it needs a service scope
---@field scoped_path? (string|table)[]  set by `annotate` when `needs_scope`: the chain down to a scoped service

-- A singleton reaches a scoped service only through transients (a singleton in between is checked on its own).
local function find_captive(bindings, binding, path, visited, found)
  for _, dependency in ipairs(binding.requires) do
    local target = bindings[dependency]
    if target ~= nil then
      if target.lifetime == Lifetime.scoped then
        local chain = copy(path)
        chain[#chain + 1] = dependency
        found[#found + 1] = { dependency = dependency, path = chain }
      elseif target.lifetime == Lifetime.transient and not visited[dependency] then
        visited[dependency] = true
        path[#path + 1] = dependency
        find_captive(bindings, target, path, visited, found)
        path[#path] = nil
      end
    end
  end
end

--- A finding of `validate` that does not fail it.
---@class hecate.container.Warning
---@field code "singleton_over_transient"
---@field key string  the singleton
---@field dependency string  the transient it requires
---@field path string[]  `{ key, dependency }`
---@field message string

--- Checks every binding, in registration order, and returns the problems found (error instances, possibly none) and
--- the warnings (plain tables, possibly none; they never fail the validation).
---@param bindings table<any, hecate.container.Binding>
---@param order (string|table)[]  keys in registration order
---@return hecate.core.Error[] problems
---@return hecate.container.Warning[] warnings
function graph.check(bindings, order)
  local problems = {}
  local warnings = {}
  local state, stack, position = {}, {}, {}

  local function visit(key)
    state[key] = "visiting"
    stack[#stack + 1] = key
    position[key] = #stack
    for _, dependency in ipairs(bindings[key].requires) do
      if bindings[dependency] ~= nil then
        if state[dependency] == "visiting" then
          local path = {}
          for i = position[dependency], #stack do path[#path + 1] = stack[i] end
          path[#path + 1] = dependency
          local rendered = render_path(path)
          problems[#problems + 1] = errors.CycleError(
            "container: dependency cycle " .. table.concat(rendered, " -> "), { context = { path = rendered } })
        elseif state[dependency] == nil then
          visit(dependency)
        end
      end
    end
    stack[#stack] = nil
    position[key] = nil
    state[key] = "done"
  end

  for _, key in ipairs(order) do
    local binding = bindings[key]
    for _, dependency in ipairs(binding.requires) do
      if bindings[dependency] == nil then
        local path = render_path({ key, dependency })
        problems[#problems + 1] = errors.MissingBindingError(
          ("container: %q requires %q, which is not bound"):format(path[1], path[2]),
          { context = { key = path[2], path = path } })
      end
    end
    if core.is_interface(key) and core.is_class(binding.definition)
      and not core.implements(binding.definition, key) then
      problems[#problems + 1] = core.ConformanceError(
        ("container: class %s bound under interface %s does not implement it"):format(
          core.name(binding.definition), graph.render(key)),
        { context = { key = graph.render(key), class = core.name(binding.definition) } })
    end
    if binding.lifetime == Lifetime.singleton then
      local found = {}
      find_captive(bindings, binding, { key }, {}, found)
      -- Only direct dependencies: a singleton in between is checked on its own, so nothing is reported twice.
      for _, dependency in ipairs(binding.requires) do
        local target = bindings[dependency]
        if target ~= nil and target.lifetime == Lifetime.transient then
          local path = render_path({ key, dependency })
          warnings[#warnings + 1] = {
            code = "singleton_over_transient", key = path[1], dependency = path[2], path = path,
            message = ("container: singleton %q depends on transient %q: the transient is built once and lives as long as the process"):format(path[1], path[2]),
          }
        end
      end
      for _, item in ipairs(found) do
        local path = render_path(item.path)
        problems[#problems + 1] = errors.LifetimeError(
          ("container: singleton %q depends on scoped service %q (%s)"):format(
            path[1], graph.render(item.dependency), table.concat(path, " -> ")),
          { context = { key = path[1], dependency = graph.render(item.dependency), path = path } })
      end
    end
    if state[key] == nil then visit(key) end
  end
  return problems, warnings
end

--- Marks each binding of a graph that `check` accepted: does constructing it need a service scope, and through which
--- chain. A scoped service needs one; a singleton never does (validated); a transient does when a dependency does.
---@param bindings table<any, hecate.container.Binding>
---@param order (string|table)[]
function graph.annotate(bindings, order)
  local function analyse(binding)
    if binding.needs_scope ~= nil then return end
    if binding.lifetime == Lifetime.scoped then
      binding.needs_scope, binding.scoped_path = true, { binding.key }
    elseif binding.lifetime == Lifetime.singleton then
      binding.needs_scope = false
    else
      binding.needs_scope = false
      for _, dependency in ipairs(binding.requires) do
        local target = bindings[dependency]
        analyse(target)
        if target.needs_scope then
          binding.needs_scope = true
          binding.scoped_path = { binding.key }
          for _, key in ipairs(target.scoped_path) do binding.scoped_path[#binding.scoped_path + 1] = key end
          break
        end
      end
    end
  end
  for _, key in ipairs(order) do
    bindings[key].needs_scope = nil
    bindings[key].scoped_path = nil
  end
  for _, key in ipairs(order) do analyse(bindings[key]) end
end

return graph
