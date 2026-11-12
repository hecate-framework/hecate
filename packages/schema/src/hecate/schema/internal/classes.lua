-- The schemas bound to classes (`schema.of`) and the presence sets of built instances (`schema.sent`).
-- Internal to `hecate.schema`: not public API. `schema.lua` requires it.
---@diagnostic disable: invisible -- the `package` fields of `Schema` are shared by the internal modules of this package
global <const> require, type, pairs, error, pcall, table

local core = require("hecate.core")
local json = require("hecate.json")
local model = require("hecate.schema.internal.model")
local validation = require("hecate.schema.internal.validation")
local base_types = require("hecate.schema.internal.base_types")

local Schema = model.Schema
local refuse, require_schema = model.refuse, model.require_schema
local make_named = base_types.make_named
local presence_sets, defaulted_for = validation.presence_sets, validation.defaulted_for
local null = json.null

---@class hecate.schema.internal.classes
local M = {}

--- The interface of a class whose instances have a representation (RFC 9110 section 3.2), declared once by the
--- class-level function `schema()` that `schema.of` calls. A class that declares it
--- (`implements = { schema.Representable }`) and has no `schema` cannot be finalised (`ConformanceError`).
--- `schema.of` refuses a class that does not declare it: the declaration is the contract.
M.Representable = core.interface("Representable", { "schema" })

--- Refuses a class that does not declare `Representable` (ArgumentError naming the class and the interface).
---@param class any
local function require_representable(class)
  if core.is_class(class) and core.implements(class, M.Representable) then return end
  local name = core.is_class(class) and core.name(class) or ("(not a class: " .. type(class) .. ")")
  error(core.ArgumentError(("schema.of: class %s does not declare the interface schema.Representable; declare it with "
    .. "`implements = { schema.Representable }` in the class options so that finalise checks its class-level schema()")
    :format(name), { context = { class = name, interface = "Representable" } }), 0)
end

--- The schema of a class: `target` is a class that declares `schema.Representable` and a class-level function
--- `schema()` returning its schema,
--- or the name of a module returning such a class (loaded at first use, so that two modules can refer to each other).
--- Resolution is lazy and memoized: `schema()` is called at first validation, coercion or emission, never at
--- declaration, so classes may refer to each other, or to themselves. The emission closes a cycle with a `$ref` to the
--- `$defs` entry named after the class (OQ-50). The result of `schema()` is emitted under the class name.
---@param target table|string  a class, or a module name
---@return hecate.schema.Schema
function M.of(target)
  if type(target) ~= "table" and type(target) ~= "string" then
    refuse("of: expects a class or a module name, got " .. type(target))
  end
  local resolved, resolving, bound_class
  -- A class that is already finalised is checked at declaration; otherwise (and for a module name) at first use.
  if type(target) == "table" and (not core.is_class(target) or core.is_finalised(target)) then
    require_representable(target)
  end
  local function resolve()
    if resolved ~= nil then return resolved end
    if resolving then error(core.ArgumentError("schema.of: the schema() of a class refers to itself while being resolved; use schema.of(Class) inside it, not Class.schema()")) end
    resolving = true
    local ok, result = pcall(function()
      local class = target
      if type(class) == "string" then class = require(class) end
      require_representable(class)
      if type(class.schema) ~= "function" then
        refuse("of: the class must declare a class-level function schema()")
      end
      bound_class = class
      local inner = class.schema()
      require_schema("of", inner)
      -- A declared property is an attribute of the instance: it must not be a member of the class (a method, an
      -- internal `__` name), which `represent` and the instance itself would then confuse with it (s2). A prototype
      -- field (a plain value on the class) is allowed: it is the default an unset attribute reads, never represented.
      local object = inner.kind == "named" and inner.item or inner
      if object.kind == "object" then
        local clashes = {}
        for name in pairs(object.properties --[[@as table]]) do
          local member = class[name]
          if type(member) == "function" or (member ~= nil and name:sub(1, 2) == "__") then clashes[#clashes + 1] = name end
        end
        table.sort(clashes)
        if #clashes > 0 then
          error(core.ArgumentError(("schema.of: %s declares the propert%s %s, which %s a member of the class; rename the property")
            :format(core.name(class), #clashes == 1 and "y" or "ies", table.concat(clashes, ", "),
              #clashes == 1 and "is" or "are"), { context = { class = core.name(class), properties = clashes } }), 0)
        end
      end
      if inner.kind == "named" then return inner end
      return make_named(core.name(class), inner, true)
    end)
    resolving = false
    if not ok then error(result, 0) end
    resolved = result
    return resolved
  end
  --- Builds an instance: the attributes are the declared properties, an explicit null leaves the attribute nil, and the
  --- presence set records which properties were sent (OQ-90). The instance is allocated with `core.allocate`: `init` is
  --- not called, so it may require arguments.
  local function build(value)
    local named = resolve()
    local object = named.item --[[@as hecate.schema.Schema]]
    local fields = named.builder(value)
    if object.kind ~= "object" then return fields end
    -- A value class is frozen after `init`, so its attributes are collected first and the frozen instance is made
    -- from them (`core.instantiate_value`); the nested parts in `fields` are already built (children first).
    local frozen = core.is_value_class(bound_class)
    local attributes = frozen and {} or core.allocate(bound_class)
    local present = {}
    local from_default = defaulted_for(value)
    for name in pairs(object.properties --[[@as table]]) do
      local member = value[name]
      if member ~= nil and not (from_default ~= nil and from_default[name]) then
        present[name] = true
        if member ~= null then attributes[name] = fields[name] end
      elseif fields[name] ~= nil then
        attributes[name] = fields[name] -- supplied by a default: the attribute is set but not sent (OQ-88, OQ-93)
      end
    end
    local instance = frozen and core.instantiate_value(bound_class, attributes) or attributes
    presence_sets[instance] = present
    return instance
  end
  return Schema("class", { options = { resolve = resolve },
    builder = build,
    representer = function(value, at) return resolve().representer(value, at) end,
    prefilter = function(value)
      local prefilter = resolve().prefilter
      return prefilter == nil or prefilter(value)
    end,
    relaxed_validator = function(value, at, out) return resolve().relaxed_validator(value, at, out) end,
    validator = function(value, at, out) return resolve().validator(value, at, out) end,
    coercer = function(value, at, out) return resolve().coercer(value, at, out) end })
end

--- Tells whether the attribute `name` was present in the content an instance was built from. An explicit
--- `null` counts as sent; an instance that was not built by `Schema:build` has sent nothing.
---@param instance table
---@param name string
---@return boolean
function M.sent(instance, name)
  local present = type(instance) == "table" and presence_sets[instance]
  return present and present[name] == true or false
end

return M
