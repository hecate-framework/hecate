-- Classes: single inheritance, flat trait composition, interface conformance checked at
-- finalisation, inherited metamethods (ADR 0007, object-model.md).
--
-- Declaration spelling (frozen by ADR 0007):
--   local Money = core.class("Money", Parent, { traits = {...}, implements = {...} })
--   function Money:init(amount) ... end
--   core.finalise(Money)
--
-- After finalisation every member the class can answer, own, composed from a trait or
-- inherited, is stored in the class table itself, so a method lookup on an instance is a
-- single `__index` table access (invariant: flattened methods).
global <const> type, tostring, pairs, ipairs, next, rawget, rawset, setmetatable, table, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")
local trait_module = require("hecate.core.trait")
local interface_module = require("hecate.core.interface")

local classes = registry.classes

-- Keys of a class table that are per class and therefore never copied from a superclass.
local NOT_INHERITED = { __index = true, __name = true }

---@class hecate.core.ClassOptions
---@field traits? (table|hecate.core.TraitUse)[]  traits composed into the class
---@field implements? table[]  interfaces checked at finalisation

local function describe(class)
  return "class " .. classes[class].name
end

local class_metatable_methods = {}

--- Instantiates a finalised class: creates the object, runs `init`.
function class_metatable_methods.__call(class, ...)
  local record = classes[class]
  if not record.finalised then
    raise.conformance(("%s is not finalised; call core.finalise before instantiating it"):format(describe(class)),
      { class = record.name })
  end
  local object = setmetatable({}, class) -- hecate: raw-metatable instance of a class
  local init = rawget(class, "init")
  if init then init(object, ...) end
  local freeze = record.freeze
  if freeze then freeze(object, class, record) end
  return object
end

function class_metatable_methods.__tostring(class) return describe(class) end

function class_metatable_methods.__newindex(class, key, value)
  local record = classes[class]
  if record.finalised then
    raise.conformance(("%s is finalised; cannot add member %s"):format(describe(class), tostring(key)),
      { class = record.name, member = tostring(key) })
  end
  rawset(class, key, value)
end

--- Declares a class. The class must be finalised with `finalise` before use.
---@param name string
---@param parent? table  superclass (finalised before this class is finalised)
---@param options? hecate.core.ClassOptions
---@return table class
local function class(name, parent, options)
  if type(name) ~= "string" or name == "" then
    raise.argument("class name must be a non-empty string, got " .. tostring(name))
  end
  if parent ~= nil and classes[parent] == nil then
    raise.argument(("class %s: superclass must be a class created with core.class"):format(name))
  end
  options = options or {}
  for _, handle in ipairs(options.implements or {}) do
    if registry.interfaces[handle] == nil then
      raise.argument(("class %s: implements expects interfaces created with core.interface"):format(name))
    end
  end
  local metatable = {} -- hecate: raw-metatable class metatable
  for key, fn in pairs(class_metatable_methods) do metatable[key] = fn end
  local declared = {}
  declared.__index = declared
  declared.__name = name
  setmetatable(declared, metatable) -- hecate: raw-metatable class metatable
  local uses = {}
  for _, entry in ipairs(options.traits or {}) do
    uses[#uses + 1] = entry
    trait_module.normalise("class " .. name, entry) -- validates the entry
  end
  classes[declared] = {
    name = name,
    parent = parent,
    uses = uses,
    interfaces = options.implements or {},
    metatable = metatable,
    finalised = false,
    origins = {},
    own = {},
  }
  return declared
end

--- Collects the interface requirements of a record: name -> origin interface name.
local function interface_requirements(record)
  local required, order = {}, {}
  for _, handle in ipairs(record.interfaces) do
    local interface_record = registry.interfaces[handle]
    for _, method in ipairs(interface_record.order) do
      if required[method] == nil then
        required[method] = interface_record.required[method]
        order[#order + 1] = method
      end
    end
  end
  return required, order
end

--- Finalises a class: resolves trait composition and interface conformance, then
--- flattens inherited and composed members into the class table. All problems are
--- reported in one ConformanceError, and the class is left untouched on failure.
--- Finalising a finalised class is a no-op.
---@param target table
---@return table target
local function finalise(target)
  local record = classes[target]
  if record == nil then raise.argument("finalise expects a class created with core.class") end
  if record.finalised then return target end
  local parent, parent_record = record.parent, nil
  if parent then
    parent_record = classes[parent]
    if not parent_record.finalised then
      raise.conformance(
        ("%s cannot be finalised before its superclass %s; finalise the superclass first"):format(
          describe(target), describe(parent)),
        { class = record.name, superclass = parent_record.name })
    end
  end

  -- Own members: everything declared on the class table so far.
  local own, fallback = {}, nil
  for key, value in next, target do
    if key == "__index" then
      if value ~= target then fallback = value end
    elseif not NOT_INHERITED[key] then
      own[key] = value
    end
  end

  local problems = {}
  local contributions, conflicts, composition_problems = trait_module.compose(own, record.uses, describe(target))
  for _, message in ipairs(composition_problems) do problems[#problems + 1] = message end
  for _, c in ipairs(conflicts) do
    problems[#problems + 1] = ("%s: conflicting method %s provided by %s and %s; define it in the class, exclude or alias one"):format(
      describe(target), c.member, c.first, c.second)
  end

  -- Conformance is checked against the members the finalised class will have.
  local function provides(member)
    if type(own[member]) == "function" or contributions[member] ~= nil then return true end
    return parent ~= nil and type(rawget(parent, member)) == "function"
  end
  local missing = {}
  local seen = {}
  for _, entry in ipairs(record.uses) do
    local handle = trait_module.normalise("class " .. record.name, entry)
    for _, req in ipairs(registry.traits[handle].requires) do
      local key = req.member
      if not provides(key) and not seen[key] then
        seen[key] = true
        missing[#missing + 1] = { member = key, origin = "trait " .. req.origin }
        problems[#problems + 1] = ("%s: missing method %s required by trait %s"):format(
          describe(target), key, req.origin)
      end
    end
  end
  local required, order = interface_requirements(record)
  for _, member in ipairs(order) do
    if not provides(member) and not seen[member] then
      seen[member] = true
      missing[#missing + 1] = { member = member, origin = required[member] }
      problems[#problems + 1] = ("%s: missing method %s required by interface %s"):format(
        describe(target), member, required[member])
    end
  end

  if #problems > 0 then
    raise.conformance(table.concat(problems, "; "),
      { class = record.name, conflicts = conflicts, missing = missing })
  end

  -- Flattening: class > trait > superclass (Schärli et al. 2003, section 3).
  for key in pairs(own) do record.own[key] = true; record.origins[key] = "class " .. record.name end
  for member, item in pairs(contributions) do
    rawset(target, member, item.fn)
    record.origins[member] = item.origin
  end
  if parent then
    for key, value in next, parent do
      if not NOT_INHERITED[key] and rawget(target, key) == nil then
        rawset(target, key, value)
        record.origins[key] = parent_record.origins[key] or ("class " .. parent_record.name)
      end
    end
    fallback = fallback or parent_record.fallback
  end
  rawset(target, "__index", target)
  if record.prepare then record.prepare(target, record) end
  record.fallback = fallback
  if fallback ~= nil then record.metatable.__index = fallback end
  record.finalised = true
  return target
end

return { class = class, finalise = finalise, NOT_INHERITED = NOT_INHERITED }
