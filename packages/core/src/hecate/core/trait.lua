-- Traits: reusable sets of methods composed flatly, with explicit conflict resolution
-- (Schärli, Ducasse, Nierstrasz, Black 2003, section 3: composition operators sum,
-- exclusion and aliasing; section 3 also fixes the precedence class > trait).
global <const> type, tostring, pairs, ipairs, setmetatable, rawequal, table, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")

local trait_metatable = { -- hecate: raw-metatable opaque handle
  __tostring = function(self) return "trait " .. registry.traits[self].name end,
  __newindex = function(self)
    raise.conformance(("trait %s is immutable"):format(registry.traits[self].name))
  end,
  __call = function(self)
    raise.conformance(("trait %s cannot be instantiated"):format(registry.traits[self].name))
  end,
}

---@class hecate.core.TraitUse
---@field [1] table  the trait
---@field exclude? string[]  names removed from the trait (Schärli et al. 2003, exclusion)
---@field alias? table<string, string>  additional names for methods (aliasing)

--- Normalises one entry of a `traits` list: a trait, or a table `{ trait, exclude=, alias= }`.
---@param owner string  description of the composing element, for messages
---@param entry table
---@return table trait
---@return table<string, boolean> exclude
---@return table<string, string> alias
local function normalise(owner, entry)
  local handle, exclude, alias = entry, {}, {}
  if registry.traits[entry] == nil and type(entry) == "table" and entry[1] ~= nil then
    handle = entry[1]
    for _, name in ipairs(entry.exclude or {}) do exclude[name] = true end
    alias = entry.alias or {}
  end
  if registry.traits[handle] == nil then
    raise.argument(owner .. ": traits must be traits created with core.trait")
  end
  return handle, exclude, alias
end

--- Computes the methods contributed by a list of trait uses.
--- Returns the contributions (name -> { fn, origin }), the list of conflicts and the
--- list of problems with exclusions and aliases.
---@param own table<string, any>  members the composing element defines itself (they win)
---@param uses table[]
---@param owner string
---@return table<string, { fn: function, origin: string }> contributions
---@return table[] conflicts
---@return string[] problems
local function compose(own, uses, owner)
  local contributions, conflicts, problems = {}, {}, {}
  for _, entry in ipairs(uses) do
    local handle, exclude, alias = normalise(owner, entry)
    local record = registry.traits[handle]
    local provided = {}
    for name, fn in pairs(record.methods) do
      provided[name] = { fn = fn, origin = record.origins[name] }
    end
    for name in pairs(exclude) do
      if provided[name] == nil then
        problems[#problems + 1] = ("%s excludes %s, which trait %s does not provide"):format(owner, name, record.name)
      else
        provided[name] = nil
      end
    end
    for original, new_name in pairs(alias) do
      local source = record.methods[original]
      if source == nil then
        problems[#problems + 1] = ("%s aliases %s, which trait %s does not provide"):format(owner, original, record.name)
      else
        provided[new_name] = { fn = source, origin = record.origins[original] }
      end
    end
    for name, item in pairs(provided) do
      if own[name] == nil then
        local previous = contributions[name]
        if previous == nil then
          contributions[name] = item
        elseif previous.fn ~= item.fn then
          conflicts[#conflicts + 1] = { member = name, first = previous.origin, second = item.origin }
        end
      end
    end
  end
  table.sort(conflicts, function(a, b) return a.member < b.member end)
  return contributions, conflicts, problems
end

---@class hecate.core.TraitOptions
---@field traits? (table|hecate.core.TraitUse)[]  traits composed into this one
---@field requires? string[]  methods the composing class must provide

--- Declares a trait. Composition of other traits is resolved at declaration time.
---@param name string
---@param methods table<string, function>
---@param options? hecate.core.TraitOptions
---@return table
local function trait(name, methods, options)
  if type(name) ~= "string" then raise.argument("trait name must be a string, got " .. type(name)) end
  if type(methods) ~= "table" then raise.argument("trait " .. name .. ": methods must be a table") end
  options = options or {}
  local owner = "trait " .. name
  local record = { name = name, methods = {}, origins = {}, requires = {}, uses = {} }
  for method, fn in pairs(methods) do
    if type(method) ~= "string" or type(fn) ~= "function" then
      raise.argument(("%s: members must be named functions, got %s = %s"):format(owner, tostring(method), type(fn)))
    end
    record.methods[method] = fn
    record.origins[method] = "trait " .. name
  end
  local contributions, conflicts, problems = compose(record.methods, options.traits or {}, owner)
  for _, c in ipairs(conflicts) do
    problems[#problems + 1] = ("%s: conflicting method %s provided by %s and %s"):format(owner, c.member, c.first, c.second)
  end
  if #problems > 0 then
    raise.conformance(table.concat(problems, "; "), { trait = name, conflicts = conflicts })
  end
  for method, item in pairs(contributions) do
    record.methods[method] = item.fn
    record.origins[method] = item.origin
  end
  for _, entry in ipairs(options.traits or {}) do
    local handle = normalise(owner, entry)
    record.uses[#record.uses + 1] = handle
  end
  -- Requirements: declared ones plus those of composed traits, minus what is provided.
  local seen = {}
  local function require_method(method, origin)
    if record.methods[method] == nil and not seen[method] then
      seen[method] = true
      record.requires[#record.requires + 1] = { member = method, origin = origin }
    end
  end
  for _, method in ipairs(options.requires or {}) do require_method(method, name) end
  for _, handle in ipairs(record.uses) do
    for _, req in ipairs(registry.traits[handle].requires) do require_method(req.member, req.origin) end
  end
  local handle = setmetatable({}, trait_metatable) -- hecate: raw-metatable opaque handle
  registry.traits[handle] = record
  return handle
end

--- Returns true when `candidate` is `target` or composes it, directly or transitively.
---@param candidate table
---@param target table
---@return boolean
local function composes(candidate, target)
  if rawequal(candidate, target) then return true end
  for _, used in ipairs(registry.traits[candidate].uses) do
    if composes(used, target) then return true end
  end
  return false
end

return { trait = trait, compose = compose, normalise = normalise, composes = composes }
