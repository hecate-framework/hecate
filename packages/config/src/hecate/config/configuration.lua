-- `Configuration`: the immutable result of `config.load` (configuration.md, "Immutability and typed access").
global <const> require, type, pairs, ipairs, table, string, tostring, error

local core = require("hecate.core")
local values = require("hecate.config.values")

local Section, List = values.Section, values.List

--- The validated, immutable configuration of a process. Read it with `get` or by field from `values()`; nothing changes
--- after `config.load` returned it.
---@class hecate.config.Configuration
---@field package _root hecate.config.Section
---@field package _index hecate.config.Node
---@field package _sources table<string, string>
---@field package _environment string
---@overload fun(root: hecate.config.Section, index: hecate.config.Node, sources: table<string, string>, environment: string): hecate.config.Configuration
local Configuration = core.class("Configuration")

---@param root hecate.config.Section
---@param index hecate.config.Node
---@param sources table<string, string>  JSON Pointer to the name of the layer that supplied the value
---@param environment string
function Configuration:init(root, index, sources, environment)
  self._root, self._index, self._sources, self._environment = root, index, sources, environment
end

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
  local segments = {}
  for segment in path:gmatch("[^.]+") do segments[#segments + 1] = segment end
  local node = self._index --[[@as hecate.config.Node?]]
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
  return read(self._root, resolve(self, "get", path))
end

--- The name of the layer that supplied the value of a declared key (`config/default.lua`, `environment variable NAME`,
--- `secret file PATH`, `schema default`), or `nil` when the key is absent.
---@param path string  dotted path
---@return string? layer
function Configuration:source(path)
  local segments = resolve(self, "source", path)
  local pointer = {}
  for i, segment in ipairs(segments) do pointer[i] = escape(segment) end
  local known = self._sources["/" .. table.concat(pointer, "/")]
  if known ~= nil then return known end
  if read(self._root, segments) == nil then return nil end
  return "schema default"
end

--- The root `Section`: every key of the configuration, read by field.
---@return hecate.config.Section
function Configuration:values()
  return self._root
end

--- The name of the environment the configuration was loaded for (the `environment` option, else `<PREFIX>_ENV`, else `production`).
---@return string
function Configuration:environment()
  return self._environment
end

local function render(value)
  if type(value) == "string" then return ("%q"):format(value) end
  return tostring(value)
end

local function collect(value, path, pointer, sources, out)
  local is_section, is_list = core.is_instance_of(value, Section), core.is_instance_of(value, List)
  local source = sources[pointer] or "schema default"
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
      local name = tostring(key)
      collect(item, path == "" and name or (path .. "." .. name), pointer .. "/" .. escape(name), sources, out)
    end
  else
    out[#out + 1] = { path, ("%s = %s (%s)"):format(path, render(value), source) }
  end
end

--- A multi-line text, one `path = value (layer)` per leaf in path order, in which secrets are `[redacted]`: the text to
--- log at boot.
---@return string
function Configuration:describe()
  local out = {}
  collect(self._root, "", "", self._sources, out)
  table.sort(out, function(a, b) return a[1] < b[1] end)
  local lines = {}
  for i, entry in ipairs(out) do lines[i] = entry[2] end
  return table.concat(lines, "\n")
end

return core.finalise(Configuration)
