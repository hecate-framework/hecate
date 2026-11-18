-- Project documentation: the page generators `hecate.doc.generate_project_documentation` uses for a user project:
-- the configuration reference from a configuration schema, and the LuaLS meta files of the schemas of a
-- project (documentation.md, "Documentation of a project"). The generated site is the documentation of the
-- project's own team: it publishes the `maintainer` audience unless the project asks for more (`audiences`,
-- OQ-144). There is no API reference: the OpenAPI contract is the external documentation of the API, and its
-- viewer is the wiring of the user (OQ-141).
-- The page generators are pure: tables in, Markdown out, deterministic. Every piece of text
-- that comes from the schema is escaped, because the schema is data of the project, not Markdown.
global <const> require, type, ipairs, pairs, next, table, string, error, tostring, math

local core = require("hecate.core")
local generated_page = require("hecate.doc.internal.generated_page")
local text_helpers = require("hecate.doc.internal.text")

--- Pages generated from the configuration and the schemas of a project.
---@class hecate.doc.project
local M = {}

--- The notice written at the top of every generated project page.
M.GENERATED = generated_page.GENERATED

--- True for a page written by this module.
---@param text any  anything is accepted: a value that is not a string is not generated
---@return boolean
function M.is_generated(text)
  return type(text) == "string" and text:find(M.GENERATED, 1, true) ~= nil
end

-- Limits for schemas that are data of the project and may be hostile or enormous.
local MAX_ROWS = 500       -- property rows of one table
local MAX_DEPTH = 6        -- nesting of object properties
local MAX_TYPE_DEPTH = 8   -- nesting of the type expression of a cell
local MAX_VALUES = 50      -- values of an enumeration shown
local MAX_SERIALISED_DEPTH = 8
local REDACTED = "[redacted]" -- what stands for the default of a secret key

local function list(value) return type(value) == "table" and value or {} end

local plain, code = text_helpers.plain, text_helpers.code

local function sorted_keys(map)
  local keys = {}
  for key in pairs(list(map)) do
    if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- JSON-like text with sorted keys: the same value is always rendered the same way.
local function serialise(value, depth)
  depth = depth or 0
  local kind = type(value)
  if kind == "string" then
    return '"' .. value:gsub('[%c"\\]', function(char)
      local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
      return named[char] or ("\\u%04x"):format(char:byte())
    end) .. '"'
  elseif kind == "number" or kind == "boolean" or kind == "nil" then
    return tostring(value)
  elseif kind ~= "table" then
    return '"<' .. kind .. '>"'
  end
  if depth >= MAX_SERIALISED_DEPTH then return "..." end
  local parts = {}
  if #value > 0 or next(value) == nil then
    for _, item in ipairs(value) do parts[#parts + 1] = serialise(item, depth + 1) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for _, key in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = serialise(tostring(key)) .. ":" .. serialise(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- The text of a default or an enumeration member: a string as it is, any other value serialised.
local function value_text(value)
  if type(value) == "string" then return value end
  return serialise(value)
end

local function unescape_pointer(name)
  return (name:gsub("~1", "/"):gsub("~0", "~"))
end

-- Follows `$ref` chains into the `$defs` of the schema document itself (JSON Schema 2020-12, 8.2.4). Returns the
-- target and the list of references crossed; an unresolvable reference is returned as it is.
local function resolve(document, node)
  local crossed = {}
  while type(node) == "table" and type(node["$ref"]) == "string" and #crossed < 16 do
    local ref = node["$ref"]
    local name = ref:match("^#/%$defs/(.+)$")
    local target = name and type(document["$defs"]) == "table" and document["$defs"][unescape_pointer(name)]
    crossed[#crossed + 1] = ref
    if type(target) ~= "table" then return node, crossed end
    node = target
  end
  return node, crossed
end

local function type_of(document, schema, depth)
  depth = depth or 0
  if type(schema) ~= "table" or depth > MAX_TYPE_DEPTH then return "any" end
  local ref = schema["$ref"]
  if type(ref) == "string" then return ref:match("([^/]+)$") or "any" end
  local kind = schema.type
  if type(kind) == "table" then
    local names = {}
    for _, name in ipairs(kind) do
      if type(name) == "string" then names[#names + 1] = name end
    end
    kind = #names > 0 and table.concat(names, " or ") or nil
  elseif type(kind) ~= "string" then
    kind = nil
  end
  if kind == "array" then return "array of " .. type_of(document, schema.items, depth + 1) end
  return kind or (schema.enum and "enum") or "any"
end

local function constraints(schema)
  local parts = {}
  if type(schema) ~= "table" then return "" end
  if type(schema.enum) == "table" then
    local values = {}
    for index, value in ipairs(schema.enum) do
      if index > MAX_VALUES then values[#values + 1] = "..."; break end
      values[#values + 1] = code(value_text(value), true)
    end
    parts[#parts + 1] = "one of " .. table.concat(values, ", ")
  end
  if schema.const ~= nil then parts[#parts + 1] = "always " .. code(value_text(schema.const), true) end
  if schema.minimum ~= nil and schema.maximum ~= nil then
    parts[#parts + 1] = ("%s to %s"):format(tostring(schema.minimum), tostring(schema.maximum))
  elseif schema.minimum ~= nil then
    parts[#parts + 1] = "at least " .. tostring(schema.minimum)
  elseif schema.maximum ~= nil then
    parts[#parts + 1] = "at most " .. tostring(schema.maximum)
  end
  if schema.minLength ~= nil then parts[#parts + 1] = "length at least " .. tostring(schema.minLength) end
  if schema.maxLength ~= nil then parts[#parts + 1] = "length at most " .. tostring(schema.maxLength) end
  if schema.pattern ~= nil then parts[#parts + 1] = "pattern " .. code(value_text(schema.pattern), true) end
  if schema.format ~= nil then parts[#parts + 1] = "format " .. code(value_text(schema.format), true) end
  return table.concat(parts, "; ")
end

-- Property rows of an object schema, nested objects flattened with dotted paths. `state` bounds the work on an
-- untrusted contract: `rows` is capped (`truncated` is set), a reference already being expanded on the
-- current path is shown as a row and not expanded again, and the nesting is limited.
local function property_rows(document, schema, prefix, state, depth, visiting)
  local target, crossed = resolve(document, schema)
  if type(target) ~= "table" or type(target.properties) ~= "table" or depth > MAX_DEPTH then return end
  for _, ref in ipairs(crossed) do
    if visiting[ref] then return end
  end
  for _, ref in ipairs(crossed) do visiting[ref] = true end
  local required = {}
  for _, name in ipairs(list(target.required)) do required[name] = true end
  for _, name in ipairs(sorted_keys(target.properties)) do
    if #state.rows >= MAX_ROWS then state.truncated = true; break end
    local property = target.properties[name]
    local path = prefix .. tostring(name)
    local resolved, property_refs = resolve(document, property)
    local nested = type(resolved) == "table" and type(resolved.properties) == "table" and depth < MAX_DEPTH
    for _, ref in ipairs(property_refs) do
      if visiting[ref] then nested = false end
    end
    if nested then
      property_rows(document, property, path .. ".", state, depth + 1, visiting)
    else
      -- A secret shows neither its default nor the values it may take (enumeration, constant): the schema of a
      -- project is published as it is, and a default is where a development password hides.
      local secret = state.secrets[path] == true
        or (type(resolved) == "table" and (resolved.writeOnly == true or resolved.format == "password"))
      local default = type(resolved) == "table" and resolved.default
      local shown = resolved
      if secret and type(resolved) == "table" then
        shown = {}
        for key, value in pairs(resolved) do
          if key ~= "enum" and key ~= "const" and key ~= "pattern" then shown[key] = value end
        end
      end
      state.rows[#state.rows + 1] = {
        path = path, type = type_of(document, property), required = required[name] == true,
        default = secret and default ~= nil and REDACTED or default,
        constraints = constraints(shown),
        description = type(property) == "table" and (property.description or (type(resolved) == "table" and resolved.description)) or nil,
      }
    end
  end
  for _, ref in ipairs(crossed) do visiting[ref] = nil end
end

local function rows_of(document, schema, secrets)
  local state = { rows = {}, secrets = {} }
  for _, path in ipairs(list(secrets)) do state.secrets[path] = true end
  property_rows(document, schema, "", state, 0, {})
  return state
end

local function table_of_properties(lines, state, with_default)
  lines[#lines + 1] = with_default and "| Key | Type | Required | Default | Constraints | Description |"
    or "| Name | Type | Required | Constraints | Description |"
  lines[#lines + 1] = with_default and "|---|---|---|---|---|---|" or "|---|---|---|---|---|"
  for _, row in ipairs(state.rows) do
    local cells = { code(row.path, true), plain(row.type), row.required and "required" or "optional" }
    if with_default then cells[#cells + 1] = row.default ~= nil and code(value_text(row.default), true) or "" end
    cells[#cells + 1] = row.constraints
    cells[#cells + 1] = plain(row.description or "")
    lines[#lines + 1] = "| " .. table.concat(cells, " | ") .. " |"
  end
  lines[#lines + 1] = ""
  if state.truncated then
    lines[#lines + 1] = ("The list is truncated: only the first %d properties are shown."):format(MAX_ROWS)
    lines[#lines + 1] = ""
  end
end

local front = generated_page.front

--- Generates the configuration reference (`configuration.md`) from the JSON Schema of the
--- configuration: one row per key, nested objects flattened with dotted paths (`$ref` into the
--- `$defs` of the schema are followed).
---
--- The page is `maintainer` documentation (front matter `audience`): the keys of the configuration are what a
--- team that runs the application needs, not part of what the application offers to its users. The default of a
--- secret key is never printed (`[redacted]`): a key is a secret when its schema says `writeOnly: true` (JSON Schema
--- 2020-12, 9.4) or `format: "password"` (OpenAPI 3.1, 4.4), or when `options.secrets` lists its dotted path (the
--- secrets of `hecate.config` are declared at load time, not in the schema).
---@param schema table  JSON Schema 2020-12 table (`schema:emit()` of the configuration schema)
---@param options? { secrets?: string[] }  `secrets`: dotted paths of the keys that hold secrets
---@return string markdown
function M.configuration_page(schema, options)
  if type(schema) ~= "table" then
    error(core.ArgumentError("doc.project.configuration_page: expects a JSON Schema table"), 2)
  end
  options = options or {}
  local lines = front("Configuration", schema.description or "Configuration keys, their types and defaults.", 50,
    "maintainer")
  local state = rows_of(schema, schema, options.secrets)
  if #state.rows == 0 then
    lines[#lines + 1] = "The configuration declares no keys."
  else
    table_of_properties(lines, state, true)
  end
  return table.concat(lines, "\n")
end

local LUA_KEYWORDS = {}
for word in ("and break do else elseif end false for function global goto if in local nil not or repeat return then true until while")
  :gmatch("%a+") do LUA_KEYWORDS[word] = true end

-- The Lua type literal of a scalar, or nil for what cannot be one (a table, a number that is not finite).
local function literal(value)
  local kind = type(value)
  if kind == "string" then return (string.format("%q", value):gsub("\\\n", "\\n")) end
  if kind == "boolean" then return tostring(value) end
  if kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then return tostring(value) end
  return nil
end

local MAX_LUA_TYPE_DEPTH = 16

local function lua_type(schema, namespace, depth)
  depth = depth or 0
  if type(schema) ~= "table" or depth > MAX_LUA_TYPE_DEPTH then return "any" end
  local ref = schema["$ref"]
  if type(ref) == "string" then
    local name = ref:match("([^/]+)$")
    return name and name:match("^[%a_][%w_]*$") and (namespace .. "." .. name) or "any"
  end
  if schema.const ~= nil then return literal(schema.const) or "any" end
  if type(schema.enum) == "table" then
    local values = {}
    for _, value in ipairs(schema.enum) do
      local text = literal(value)
      if not text then return "any" end
      values[#values + 1] = text
    end
    return #values > 0 and table.concat(values, "|") or "any"
  end
  local alternatives = type(schema.anyOf) == "table" and schema.anyOf or type(schema.oneOf) == "table" and schema.oneOf
  if alternatives then
    local parts = {}
    for _, alternative in ipairs(alternatives) do parts[#parts + 1] = lua_type(alternative, namespace, depth + 1) end
    return #parts > 0 and table.concat(parts, "|") or "any"
  end
  if type(schema.allOf) == "table" then
    return #schema.allOf == 1 and lua_type(schema.allOf[1], namespace, depth + 1) or "any"
  end
  local kind = schema.type
  if type(kind) == "table" then
    local parts = {}
    for _, name in ipairs(kind) do
      parts[#parts + 1] = lua_type({ type = name, items = schema.items, properties = schema.properties,
        additionalProperties = schema.additionalProperties }, namespace, depth + 1)
    end
    return #parts > 0 and table.concat(parts, "|") or "any"
  end
  if kind == "string" then return "string" end
  if kind == "integer" then return "integer" end
  if kind == "number" then return "number" end
  if kind == "boolean" then return "boolean" end
  if kind == "null" then return "nil" end
  if kind == "array" then
    local item = lua_type(schema.items, namespace, depth + 1)
    return (item:find("|", 1, true) and "(" .. item .. ")" or item) .. "[]"
  end
  if kind == "object" then
    local additional = schema.additionalProperties
    if type(additional) == "table" and not schema.properties then
      return "table<string, " .. lua_type(additional, namespace, depth + 1) .. ">"
    end
    return "table"
  end
  return "any"
end

local function one_line(text)
  return (tostring(text):gsub("%s*[\r\n]+%s*", " "))
end

--- Generates a LuaLS `---@meta` file for the named schemas of a project (`schema:emit()` results
--- keyed by name, or the `$defs` of one): an object schema becomes a `---@class` with one
--- `---@field` per property, an enumeration an `---@alias`. Names are qualified by `namespace`
--- (`<namespace>.<name>`), so that a `$ref` resolves. Deterministic: names and properties are sorted.
---@param schemas table<string, table>  JSON Schema 2020-12 tables by name
---@param namespace string  Lua module name the types live in (e.g. `shop.schemas`)
---@return string meta  Lua source of the declaration file
function M.meta(schemas, namespace)
  local function valid_namespace()
    if type(namespace) ~= "string" then return false end
    for segment in (namespace .. "."):gmatch("([^.]*)%.") do
      if not segment:match("^[%a_][%w_]*$") then return false end
    end
    return true
  end
  if type(schemas) ~= "table" or not valid_namespace() then
    error(core.ArgumentError("doc.project.meta: expects named schemas and a namespace such as `shop.schemas`"), 2)
  end
  for name in pairs(schemas) do
    if type(name) ~= "string" then
      error(core.ArgumentError("doc.project.meta: the schemas must be keyed by name (a string)"), 2)
    end
  end
  local lines = { "---@meta " .. namespace, "-- Generated by hecate.doc from the schemas of the project. Do not edit.", "" }
  for _, name in ipairs(sorted_keys(schemas)) do
    if not name:match("^[%a_][%w_]*$") or LUA_KEYWORDS[name] then
      error(core.ArgumentError(("doc.project.meta: the schema name %q is not a Lua identifier"):format(name)), 2)
    end
    local schema = schemas[name]
    local qualified = namespace .. "." .. name
    if type(schema) == "table" and type(schema.properties) == "table" then
      for key in pairs(schema.properties) do
        if type(key) ~= "string" then
          error(core.ArgumentError(("doc.project.meta: the properties of %s must be keyed by name (a string)"):format(name)), 2)
        end
      end
      if schema.description then lines[#lines + 1] = "--- " .. one_line(schema.description) end
      lines[#lines + 1] = "---@class " .. qualified
      local required = {}
      for _, key in ipairs(list(schema.required)) do required[key] = true end
      for _, key in ipairs(sorted_keys(schema.properties)) do
        local property = schema.properties[key]
        local field = key:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[key] and key or ("[" .. literal(key) .. "]")
        local text = ("---@field %s%s %s"):format(field, required[key] and "" or "?", lua_type(property, namespace))
        if type(property) == "table" and property.description then
          text = text .. "  " .. one_line(property.description)
        end
        lines[#lines + 1] = text
      end
    else
      lines[#lines + 1] = ("---@alias %s %s"):format(qualified, lua_type(schema, namespace))
    end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

return M
