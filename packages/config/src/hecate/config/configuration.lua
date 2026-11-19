-- `Configuration`: the immutable result of `config.load` (configuration.md, "Immutability and typed access").
global <const> require, type, pairs, ipairs, table, string, tostring, error, rawequal

local core = require("hecate.core")
local values = require("hecate.config.values")

local Section, List = values.Section, values.List

--- The internals of each configuration, keyed by `Configuration` object: private to this module and weak-keyed, so that
--- no field of the object can be read or replaced.
---@class hecate.config.ConfigurationState
---@field root hecate.config.Section
---@field index hecate.config.Node
---@field sources table<string, string>
---@field environment string
---@field declaration hecate.schema.Schema  the object schema of every declared key
---@field secrets string[]  dotted paths of the secret keys, sorted

---@type table<hecate.config.Configuration, hecate.config.ConfigurationState>
local state = core.weak_table("k")

--- The validated, immutable configuration of a process. Read it with `get` or by field from `values()`; nothing changes
--- after `config.load` returned it. Invariant "configuration is immutable after boot": the object is a value class of
--- `hecate.core` with no field (a write raises `hecate.core.ConformanceError`), compared by identity.
---@class hecate.config.Configuration
---@overload fun(root: hecate.config.Section, index: hecate.config.Node, sources: table<string, string>, environment: string, declaration: hecate.schema.Schema, secrets: string[]): hecate.config.Configuration
local Configuration = core.value_class("Configuration")

---@param root hecate.config.Section
---@param index hecate.config.Node
---@param sources table<string, string>  JSON Pointer to the name of the layer that supplied the value (not copied: the caller gives it up)
---@param environment string
---@param declaration hecate.schema.Schema  the object schema of every declared key (not copied: the caller gives it up)
---@param secrets string[]  dotted paths of the secret keys, sorted (not copied)
function Configuration:init(root, index, sources, environment, declaration, secrets)
  state[self] = { root = root, index = index, sources = sources, environment = environment,
    declaration = declaration, secrets = secrets }
end

--- Identity, not the structural equality of value classes (a configuration has no field to compare).
---@param other any
---@return boolean
function Configuration:__eq(other) return rawequal(self, other) end

local function escape(segment)
  return (tostring(segment):gsub("~", "~0"):gsub("/", "~1"))
end

--- Checks a dotted path against the declared keys.
---@param self hecate.config.Configuration
---@param method string
---@param path any
---@return string[] segments
local function resolve(self, method, path)
  if type(path) ~= "string" or path == "" then
    error(core.ArgumentError(("config.Configuration.%s: path must be a non-empty string, got %s"):format(method,
      type(path) == "string" and "an empty string" or type(path))), 3)
  end
  if path:find("^%.") or path:find("%.$") or path:find("..", 1, true) then
    error(core.ArgumentError(("config.Configuration.%s: malformed path %q (an empty segment, or a leading or trailing dot)"):format(
      method, path), { context = { path = path } }), 3)
  end
  local segments = {}
  for segment in path:gmatch("[^.]+") do segments[#segments + 1] = segment end
  local node = state[self].index --[[@as hecate.config.Node?]]
  for position, segment in ipairs(segments) do
    if node == nil then break end -- inside a map: member names are not declared
    if node.kind ~= "object" then
      if node.kind == "map" then
        node = nil
      else
        error(core.ArgumentError(("config.Configuration.%s: %s is not a key with members (it is a value of %s)"):format(
          method, table.concat(segments, ".", 1, position - 1), node.schema.kind), { context = { path = path } }), 3)
      end
    else
      local child = node.children[segment]
      if child == nil then
        error(core.ArgumentError(("config.Configuration.%s: %s is not a declared key"):format(method,
          table.concat(segments, ".", 1, position)), { context = { path = path } }), 3)
      end
      node = child
    end
  end
  return segments
end

local function read(root, segments)
  local value = root
  for _, segment in ipairs(segments) do
    if not core.is_instance_of(value, Section) then return nil end
    value = value[segment]
  end
  return value
end

--- The value of a declared key, typed by its schema: a scalar, a secret object, a `Section` or a `List`; `nil` for an
--- optional key that no layer supplied. A path that the schema does not declare is a programmer error.
---@param path string  dotted path, for example `database.port`
---@return any value
function Configuration:get(path)
  return read(state[self].root, resolve(self, "get", path))
end

--- The name of the layer that supplied the value of a declared key (`config/default.lua`, `environment variable NAME`,
--- `secret file PATH`, `schema default`), or `nil` when the key is absent.
---@param path string  dotted path
---@return string? layer
function Configuration:source(path)
  local segments = resolve(self, "source", path)
  local pointer = {}
  for i, segment in ipairs(segments) do pointer[i] = escape(segment) end
  local known = state[self].sources["/" .. table.concat(pointer, "/")]
  if known ~= nil then return known end
  if read(state[self].root, segments) == nil then return nil end
  return "schema default"
end

--- The root `Section`: every key of the configuration, read by field.
---@return hecate.config.Section
function Configuration:values()
  return state[self].root
end

local MAX_REFERENCE_DEPTH = 64

--- The `properties` of the object that an emitted subschema describes, through `$ref` (into `$defs`) and `anyOf`
--- (`nullable`); `nil` when it describes no object.
local function properties_of(node, defs, depth)
  if depth > MAX_REFERENCE_DEPTH then return nil end
  if node.properties ~= nil then return node.properties end
  local reference = node["$ref"]
  if type(reference) == "string" then
    local name = reference:match("^#/%$defs/(.+)$")
    local target = name ~= nil and defs ~= nil and defs[name] or nil
    if target ~= nil then return properties_of(target, defs, depth + 1) end
  end
  if node.anyOf ~= nil then
    for _, alternative in ipairs(node.anyOf) do
      local found = properties_of(alternative, defs, depth + 1)
      if found ~= nil then return found end
    end
  end
  return nil
end

--- Marks the key at a dotted path `writeOnly` in an emitted document (a fresh table: the marks touch no declaration).
local function mark_write_only(document, path)
  local node = document
  for segment in path:gmatch("[^.]+") do
    local properties = properties_of(node, document["$defs"], 0)
    node = properties and properties[segment]
    if node == nil then
      error(core.ArgumentError(("config.Configuration.schema: the secret %s is not in the emitted schema"):format(path),
        { context = { path = path } }), 0)
    end
  end
  node.writeOnly = true
end

--- The JSON Schema (2020-12) of every declared key, the framework keys included: what a tool needs to document the
--- configuration. A new table at each call, so that a caller cannot change what the next one reads.
---
--- Every key declared secret (`secrets`, the `secrets` option of `config.load`) carries `writeOnly = true` (JSON Schema
--- 2020-12, 9.4). The `default` of such a key stays in the schema: **a consumer must honour `writeOnly` and never
--- print, log or document the `default` (nor any example) of a key marked so**. The path rules are those of `secrets`:
--- a secret is a declared leaf, found by its dotted path through objects (also optional, with a default, nullable or
--- named); a leaf that is a list (also of objects) is marked as a whole (its items are not addressable, and inherit the mark; a map is not a leaf, so it cannot be declared secret).
--- A named object used at several places is emitted once in `$defs`: a secret inside it marks that key for every use.
---@return table schema
function Configuration:schema()
  local document = state[self].declaration:to_json_schema()
  for _, path in ipairs(state[self].secrets) do mark_write_only(document, path) end
  return document
end

--- The dotted paths of the keys declared secret at load time (the `secrets` option), sorted. A new list at each call.
--- `schema` marks the same keys `writeOnly`.
---@return string[] paths
function Configuration:secrets()
  return { table.unpack(state[self].secrets) }
end

--- The name of the environment the configuration was loaded for (the `environment` option, else `<PREFIX>_ENV`, else `production`).
---@return string
function Configuration:environment()
  return state[self].environment
end

-- The escaping of `describe()`, the same on every Lua version (not `%q`, whose output keeps a line end of the value as
-- a real line end): every control character is written as an escape, so a text of `describe()` is one line per leaf
-- whatever the values, the map keys and the sources (a value cannot forge a line of the boot log).
local CONTROL_ESCAPES = { ["\n"] = "\\n", ["\r"] = "\\r" }

local function escape_control(character)
  return CONTROL_ESCAPES[character] or ("\\%03d"):format(character:byte())
end

--- A text with its control characters (bytes 0 to 31 and 127) escaped as `\n`, `\r` or `\ddd` (three decimal digits).
local function unbroken(text)
  return (text:gsub("[%c]", escape_control))
end

--- A value as `describe()` shows it: a string between double quotes, with `\` and `"` escaped too; anything else through
--- `tostring` (a secret object gives `[redacted]`), with its control characters escaped.
local function render(value)
  if type(value) == "string" then return '"' .. unbroken((value:gsub('[\\"]', "\\%0"))) .. '"' end
  return unbroken(tostring(value))
end

local function collect(value, path, pointer, sources, out)
  local is_section, is_list = core.is_instance_of(value, Section), core.is_instance_of(value, List)
  local source = unbroken(sources[pointer] or "schema default")
  if is_list then
    local items = {}
    for index, item in ipairs(value) do items[index] = render(item) end
    out[#out + 1] = { path, ("%s = {%s} (%s)"):format(path, table.concat(items, ", "), source) }
  elseif is_section then
    local empty = true
    for _ in pairs(value) do empty = false break end
    if empty then
      out[#out + 1] = { path, ("%s = {} (%s)"):format(path, source) }
      return
    end
    for key, item in pairs(value) do
      local name = unbroken(tostring(key))
      collect(item, path == "" and name or (path .. "." .. name), pointer .. "/" .. escape(key), sources, out)
    end
  else
    out[#out + 1] = { path, ("%s = %s (%s)"):format(path, render(value), source) }
  end
end

--- A multi-line text, one `path = value (layer)` per leaf in path order, in which secrets are `[redacted]`: the text to
--- log at boot. A string is shown between double quotes; the control characters of values, map keys and layers are
--- escaped (`\n`, `\r`, `\ddd`), so there is exactly one line per leaf.
---@return string
function Configuration:describe()
  local out = {}
  collect(state[self].root, "", "", state[self].sources, out)
  table.sort(out, function(a, b) return a[1] < b[1] end)
  local lines = {}
  for i, entry in ipairs(out) do lines[i] = entry[2] end
  return table.concat(lines, "\n")
end

return core.finalise(Configuration)
