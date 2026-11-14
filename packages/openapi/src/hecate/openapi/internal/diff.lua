-- The contract diff: compares two OpenAPI 3.1 documents (tables, as `openapi.build` returns them) and classifies every
-- change as breaking or not for a client of the API (docs/architecture/schemas-and-contracts.md, "hecate.openapi").
-- Schemas are Schema Objects of JSON Schema 2020-12 (OpenAPI 3.1 section 4.8.24); `$ref` into `components.schemas`
-- is resolved on each side (section 4.8.24, JSON Schema 2020-12 section 8.2.3.1). A request schema (parameter, body)
-- is an input: a change that rejects what the old contract accepted is breaking. A response schema is an output: a
-- change that withdraws what the old contract promised is breaking. The classification of the cases the
-- specification does not list is recorded in OQ-129 (11).
global <const> require, type, pairs, ipairs, error, table, string, tostring, math

local core = require("hecate.core")
local json = require("hecate.json")

---@class hecate.openapi.Change
---@field kind string  a stable identifier of the rule, such as `property_removed`
---@field breaking boolean
---@field path string  where: `METHOD /path`, then the location inside the operation
---@field message string  never holds a value of the contract (an enum value, a bound, a pattern)

local diff = {}

local METHODS <const> = { get = "GET", put = "PUT", post = "POST", delete = "DELETE", options = "OPTIONS",
  head = "HEAD", patch = "PATCH", trace = "TRACE" }
local REF_PREFIX <const> = "^#/components/schemas/(.+)$"
local MAX_DEPTH <const> = 64
local JSON_TYPES <const> = { "array", "boolean", "integer", "null", "number", "object", "string" }

-- Keywords whose change is reported as unanalysed (and breaking, the conservative reading).
local OPAQUE <const> = { "allOf", "anyOf", "oneOf", "not", "const", "if", "then", "else", "prefixItems",
  "patternProperties", "propertyNames", "contains", "dependentRequired", "dependentSchemas",
  "unevaluatedProperties", "unevaluatedItems" }
-- Input bounds: a larger value is stricter for a lower bound, a smaller one for an upper bound.
local LOWER <const> = { "minimum", "exclusiveMinimum", "minLength", "minItems", "minProperties" }
local UPPER <const> = { "maximum", "exclusiveMaximum", "maxLength", "maxItems", "maxProperties" }
local CONSTRAINTS <const> = { "pattern", "format", "multipleOf", "uniqueItems" }

local function canonical(value)
  if value == nil then return "" end
  return json.encode(value, { canonical = true })
end

local function sorted_union(a, b)
  local seen, keys = {}, {}
  for _, map in ipairs({ a, b }) do
    for key in pairs(map) do
      if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
    end
  end
  table.sort(keys)
  return keys
end

local function as_table(value)
  if type(value) == "table" then return value end
  return {}
end

local function add(context, kind, breaking, path, message)
  context.changes[#context.changes + 1] = { kind = kind, breaking = breaking, path = path, message = message }
end

--- Follows `$ref` into `components.schemas` of `document`; an unresolvable reference is the empty schema.
local function resolve(document, value)
  local hops = 0
  while type(value) == "table" and type(value["$ref"]) == "string" and hops < MAX_DEPTH do
    local name = string.match(value["$ref"], REF_PREFIX)
    local schemas = as_table(as_table(document.components).schemas)
    value = name and schemas[name] or {}
    hops = hops + 1
  end
  return as_table(value)
end

--- The set of types a schema names, or nil when it names none (every type is accepted).
local function type_set(schema)
  local declared = schema.type
  if declared == nil then return nil end
  local set = {}
  if type(declared) == "string" then declared = { declared } end
  for _, name in ipairs(as_table(declared)) do set[name] = true end
  return set
end

--- Whether a schema with type set `set` accepts an instance of JSON type `name` (an integer is also a number).
local function accepts(set, name)
  return set == nil or set[name] == true or (name == "integer" and set.number == true)
end

local function type_key(set)
  if set == nil then return "" end
  local names = {}
  for name in pairs(set) do names[#names + 1] = name end
  table.sort(names)
  return table.concat(names, ",")
end

local function value_set(list)
  if type(list) ~= "table" then return nil end
  local set = {}
  for _, value in ipairs(list) do set[canonical(value)] = true end
  return set
end

local function member_set(list)
  local set = {}
  for _, name in ipairs(as_table(list)) do set[name] = true end
  return set
end

local function compare_types(context, old, new, where, input)
  local old_set, new_set = type_set(old), type_set(new)
  if type_key(old_set) == type_key(new_set) then return end
  if not input then
    add(context, "type_changed", true, where, "the type of a response value changed")
    return
  end
  for _, name in ipairs(JSON_TYPES) do
    if accepts(old_set, name) and not accepts(new_set, name) then
      add(context, "type_narrowed", true, where, "the input type was narrowed")
      return
    end
  end
  add(context, "type_widened", false, where, "the input type was widened")
end

local function compare_enum(context, old, new, where, input)
  local old_set, new_set = value_set(old.enum), value_set(new.enum)
  if old_set == nil and new_set == nil then return end
  local removed, added = false, false
  if old_set and new_set then
    for key in pairs(old_set) do if not new_set[key] then removed = true end end
    for key in pairs(new_set) do if not old_set[key] then added = true end end
  elseif old_set then
    added = true
  else
    removed = true
  end
  -- A value removed narrows an input and is harmless in an output; a value added does the reverse.
  if removed then add(context, "enum_values_removed", input, where, "enum values were removed") end
  if added then add(context, "enum_values_added", not input, where, "enum values were added") end
end

local function compare_bounds(context, old, new, where)
  for _, group in ipairs({ { LOWER, 1 }, { UPPER, -1 } }) do
    for _, keyword in ipairs(group[1]) do
      local before, after = old[keyword], new[keyword]
      if type(before) == "number" or type(after) == "number" then
        local sign = group[2]
        local stricter = type(after) == "number" and (type(before) ~= "number" or (after - before) * sign > 0)
        local looser = type(before) == "number" and (type(after) ~= "number" or (after - before) * sign < 0)
        if stricter then
          add(context, "bound_narrowed", true, where, keyword .. " became stricter")
        elseif looser then
          add(context, "bound_widened", false, where, keyword .. " became looser")
        end
      end
    end
  end
end

local function compare_constraints(context, old, new, where)
  for _, keyword in ipairs(CONSTRAINTS) do
    if canonical(old[keyword]) ~= canonical(new[keyword]) then
      if new[keyword] == nil or new[keyword] == false then
        add(context, "constraint_widened", false, where, keyword .. " was removed")
      else
        add(context, "constraint_narrowed", true, where, keyword .. " was added or changed")
      end
    end
  end
end

local compare_schema

local function compare_required(context, old, new, where, input)
  local old_set, new_set = member_set(old.required), member_set(new.required)
  for _, name in ipairs(sorted_union(old_set, new_set)) do
    if new_set[name] and not old_set[name] then
      -- A property that inputs must now carry breaks callers; one that outputs now always carry breaks nobody.
      add(context, "required_added", input, where, ("property %s became required"):format(name))
    elseif old_set[name] and not new_set[name] then
      add(context, "required_removed", not input, where, ("property %s is no longer required"):format(name))
    end
  end
end

local function compare_properties(context, old, new, where, input, depth)
  local old_map, new_map = as_table(old.properties), as_table(new.properties)
  for _, name in ipairs(sorted_union(old_map, new_map)) do
    local at = where .. "/properties/" .. name
    if old_map[name] ~= nil and new_map[name] ~= nil then
      compare_schema(context, old_map[name], new_map[name], at, input, depth + 1)
    elseif old_map[name] ~= nil then
      -- Removing an input property breaks callers only when the new schema refuses unknown properties.
      local breaking = not input or new.additionalProperties == false
      add(context, "property_removed", breaking, at, ("property %s was removed"):format(name))
    else
      add(context, "property_added", false, at, ("property %s was added"):format(name))
    end
  end
end

local function compare_opaque(context, old, new, where, input)
  for _, keyword in ipairs(OPAQUE) do
    if canonical(old[keyword]) ~= canonical(new[keyword]) then
      add(context, "schema_changed", true, where, keyword .. " changed; the change is not analysed")
    end
  end
  if canonical(old.additionalProperties) ~= canonical(new.additionalProperties) then
    if input and old.additionalProperties == false and new.additionalProperties ~= false then
      add(context, "additional_properties_widened", false, where, "unknown properties are now accepted")
    else
      add(context, "schema_changed", true, where, "additionalProperties changed; the change is not analysed")
    end
  end
end

--- Compares two schemas; `input` selects the direction. `where` locates the schema in the operation.
function compare_schema(context, raw_old, raw_new, where, input, depth)
  if depth > MAX_DEPTH then return end
  local key
  if type(raw_old) == "table" and type(raw_new) == "table" and (raw_old["$ref"] or raw_new["$ref"]) then
    key = tostring(raw_old["$ref"]) .. "|" .. tostring(raw_new["$ref"])
    if context.active[key] then return end
    context.active[key] = true
  end
  local old, new = resolve(context.old, raw_old), resolve(context.new, raw_new)
  compare_types(context, old, new, where, input)
  compare_enum(context, old, new, where, input)
  compare_required(context, old, new, where, input)
  compare_properties(context, old, new, where, input, depth)
  if input then
    compare_bounds(context, old, new, where)
    compare_constraints(context, old, new, where)
  end
  if old.items ~= nil and new.items ~= nil then
    compare_schema(context, old.items, new.items, where .. "/items", input, depth + 1)
  elseif old.items ~= nil or new.items ~= nil then
    add(context, "schema_changed", true, where, "items was added or removed; the change is not analysed")
  end
  compare_opaque(context, old, new, where, input)
  if key then context.active[key] = nil end
end

--- Compares two `content` maps (media type to Media Type Object). `input` is true for a request body.
local function compare_content(context, old, new, where, input)
  local old_map, new_map = as_table(old), as_table(new)
  for _, media_type in ipairs(sorted_union(old_map, new_map)) do
    local at = where .. "/" .. media_type
    if old_map[media_type] ~= nil and new_map[media_type] ~= nil then
      compare_schema(context, as_table(old_map[media_type]).schema, as_table(new_map[media_type]).schema, at, input, 0)
    elseif old_map[media_type] ~= nil then
      add(context, "media_type_removed", true, at, "a media type was removed")
    else
      add(context, "media_type_added", false, at, "a media type was added")
    end
  end
end

local function parameter_index(operation)
  local index = {}
  for _, parameter in ipairs(as_table(operation.parameters)) do
    if type(parameter) == "table" and type(parameter.name) == "string" then
      index[tostring(parameter["in"]) .. " " .. parameter.name] = parameter
    end
  end
  return index
end

local function compare_parameters(context, old, new, where)
  local old_index, new_index = parameter_index(old), parameter_index(new)
  for _, key in ipairs(sorted_union(old_index, new_index)) do
    local at = where .. " parameters/" .. (string.gsub(key, " ", "/", 1))
    local before, after = old_index[key], new_index[key]
    if before and after then
      local was, is = before.required == true, after.required == true
      if is and not was then
        add(context, "parameter_required", true, at, "an optional parameter became required")
      elseif was and not is then
        add(context, "parameter_optional", false, at, "a required parameter became optional")
      end
      compare_schema(context, before.schema, after.schema, at, true, 0)
    elseif before then
      add(context, "parameter_removed", true, at, "a parameter was removed")
    elseif after.required == true then
      add(context, "parameter_added_required", true, at, "a required parameter was added")
    else
      add(context, "parameter_added", false, at, "an optional parameter was added")
    end
  end
end

local function compare_request_body(context, old, new, where)
  local at = where .. " requestBody"
  local before, after = old.requestBody, new.requestBody
  if before == nil and after == nil then return end
  if before == nil then
    local required = as_table(after).required == true
    add(context, required and "request_body_added_required" or "request_body_added", required, at,
      required and "a required request body was added" or "an optional request body was added")
    return
  end
  if after == nil then
    add(context, "request_body_removed", false, at, "the request body was removed")
    return
  end
  local was, is = as_table(before).required == true, as_table(after).required == true
  if is and not was then
    add(context, "request_body_required", true, at, "the request body became required")
  elseif was and not is then
    add(context, "request_body_optional", false, at, "the request body became optional")
  end
  compare_content(context, as_table(before).content, as_table(after).content, at, true)
end

local function compare_responses(context, old, new, where)
  local old_map, new_map = as_table(old.responses), as_table(new.responses)
  for _, code in ipairs(sorted_union(old_map, new_map)) do
    local at = where .. " responses/" .. tostring(code)
    if old_map[code] ~= nil and new_map[code] ~= nil then
      compare_content(context, as_table(old_map[code]).content, as_table(new_map[code]).content, at, false)
    elseif old_map[code] ~= nil then
      add(context, "response_removed", true, at, "a response was removed")
    else
      add(context, "response_added", false, at, "a response was added")
    end
  end
end

local function compare_operation(context, old, new, where)
  compare_parameters(context, old, new, where)
  compare_request_body(context, old, new, where)
  compare_responses(context, old, new, where)
end

local function operations_of(item)
  local operations = {}
  for key, operation in pairs(as_table(item)) do
    if METHODS[key] and type(operation) == "table" then operations[key] = operation end
  end
  return operations
end

local function before(a, b)
  if a.path ~= b.path then return a.path < b.path end
  if a.kind ~= b.kind then return a.kind < b.kind end
  if a.message ~= b.message then return a.message < b.message end
  return (a.breaking and 1 or 0) < (b.breaking and 1 or 0)
end

--- Compares two documents. See `hecate.openapi.diff`.
---@param old table
---@param new table
---@return hecate.openapi.Change[]
function diff.compare(old, new)
  for index = 1, 2 do
    local document = new
    if index == 1 then document = old end
    if type(document) ~= "table" then
      error(core.ArgumentError(("hecate.openapi.diff: argument %d must be an OpenAPI document (a table), got %s")
        :format(index, type(document)), { context = { argument = index } }), 0)
    end
  end
  local context = { old = old, new = new, changes = {}, active = {} }
  local old_paths, new_paths = as_table(old.paths), as_table(new.paths)
  for _, path in ipairs(sorted_union(old_paths, new_paths)) do
    if old_paths[path] == nil then
      add(context, "path_added", false, path, "a path was added")
    elseif new_paths[path] == nil then
      add(context, "path_removed", true, path, "a path was removed")
    else
      local old_ops, new_ops = operations_of(old_paths[path]), operations_of(new_paths[path])
      for _, method in ipairs(sorted_union(old_ops, new_ops)) do
        local where = METHODS[method] .. " " .. path
        if old_ops[method] == nil then
          add(context, "operation_added", false, where, "an operation was added")
        elseif new_ops[method] == nil then
          add(context, "operation_removed", true, where, "an operation was removed")
        else
          compare_operation(context, old_ops[method], new_ops[method], where)
        end
      end
    end
  end
  table.sort(context.changes, before)
  return context.changes
end

return diff
