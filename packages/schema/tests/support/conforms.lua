-- An independent, structural checker of a JSON Schema 2020-12 subset. It reads only the keywords of a JSON Schema
-- document, never a Lua schema, so that it can be validated against the official test suite
-- (`json_schema_suite_test.lua`) and then used as the oracle of the emission (`emit_test.lua`).
--
-- Keywords (validation vocabulary, sections 6.1 to 6.5; applicator vocabulary, sections 10.2.1.2, 10.2.1.3, 10.3.1.2,
-- 10.3.2.1, 10.3.2.3; core vocabulary, section 8.2.3.1 for `$ref` to a JSON Pointer fragment of the same document):
-- type, enum, const, minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf, minLength, maxLength,
-- minItems, maxItems, uniqueItems, items, required, properties, additionalProperties, minProperties, maxProperties,
-- anyOf, oneOf, $ref, $defs; `true` and `false` are schemas. Not supported (the caller must not pass them): `pattern`,
-- `format`, and every other keyword.
local json = require("hecate.json")
local null = json.null

local M = {}

local function finite(value) return type(value) == "number" and value == value and math.abs(value) ~= math.huge end

-- A table marked by `json.array` or `json.object` (every decoded one) keeps its kind; an unmarked table is an array
-- when its keys are 1..n, an object when all its keys are strings, and "empty" when it has no key (ambiguous).
local function kind_of(value)
  if type(value) ~= "table" or value == null then return nil end
  if json.is_array(value) then return "array" end
  if json.is_object(value) then return "object" end
  local length, count, strings = #value, 0, true
  for key in next, value do
    count = count + 1
    if type(key) ~= "string" then strings = false end
  end
  if count == 0 then return "empty" end
  if count == length then return "array" end
  return strings and "object" or nil
end

local function json_type_is(value, name)
  if name == "null" then return value == null end
  if name == "boolean" then return type(value) == "boolean" end
  if name == "string" then return type(value) == "string" end
  if name == "number" then return finite(value) end
  if name == "integer" then return finite(value) and value == math.floor(value) end -- section 6.1.1
  if name == "array" or name == "object" then
    local kind = kind_of(value)
    return kind == name or kind == "empty"
  end
  return false
end

-- Instance equality of section 4.2.2: numbers by mathematical value, arrays element-wise, objects member-wise.
local function equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" or a == null or b == null then return false end
  local kind_a, kind_b = kind_of(a), kind_of(b)
  if kind_a ~= kind_b and kind_a ~= "empty" and kind_b ~= "empty" then return false end
  if kind_a == "array" and kind_b == "array" then
    if #a ~= #b then return false end
    for i = 1, #a do
      if not equal(a[i], b[i]) then return false end
    end
    return true
  end
  for key, member in pairs(a) do
    if b[key] == nil or not equal(member, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end
M.equal = equal

-- Resolves a same-document reference "#" or "#/a/b" (RFC 6901 tokens, `~1` and `~0`); nil when it does not resolve.
local function resolve(root, reference)
  if reference == "#" then return root end
  local pointer = reference:match("^#(/.*)$")
  if not pointer then return nil end
  local node = root
  for token in pointer:gmatch("/([^/]*)") do
    local name = token:gsub("~1", "/"):gsub("~0", "~")
    if type(node) ~= "table" then return nil end
    node = node[name] or node[(tonumber(name) or -1) + 1] -- array indices are 0-based in a pointer
    if node == nil then return nil end
  end
  return node
end
M.resolve = resolve

local function conforms(node, value, root)
  if node == true then return true end
  if node == false then return false end
  if node["$ref"] then
    local target = resolve(root, node["$ref"])
    if target == nil then error("unresolvable $ref " .. tostring(node["$ref"]), 0) end
    if not conforms(target, value, root) then return false end
  end
  if node.oneOf then -- section 10.2.1.3: exactly one subschema
    local matches = 0
    for _, alternative in ipairs(node.oneOf) do
      if conforms(alternative, value, root) then matches = matches + 1 end
    end
    if matches ~= 1 then return false end
  end
  if node.anyOf then -- section 10.2.1.2
    local found = false
    for _, alternative in ipairs(node.anyOf) do
      if conforms(alternative, value, root) then found = true break end
    end
    if not found then return false end
  end
  if node.const ~= nil and not equal(node.const, value) then return false end
  if node.enum then
    local found = false
    for _, constant in ipairs(node.enum) do
      if equal(constant, value) then found = true break end
    end
    if not found then return false end
  end
  if node.type then
    local names = type(node.type) == "table" and node.type or { node.type }
    local found = false
    for _, name in ipairs(names) do
      if json_type_is(value, name) then found = true break end
    end
    if not found then return false end
  end
  if type(value) == "string" then
    local length = utf8.len(value)
    if length == nil then return false end
    if node.minLength and length < node.minLength then return false end
    if node.maxLength and length > node.maxLength then return false end
  end
  if type(value) == "number" then
    if node.minimum and value < node.minimum then return false end
    if node.maximum and value > node.maximum then return false end
    if node.exclusiveMinimum and value <= node.exclusiveMinimum then return false end
    if node.exclusiveMaximum and value >= node.exclusiveMaximum then return false end
    if node.multipleOf and math.fmod(value, node.multipleOf) ~= 0 then return false end
  end
  local kind = kind_of(value)
  if kind == "array" or (kind == "empty" and node.type == "array") then
    if node.minItems and #value < node.minItems then return false end
    if node.maxItems and #value > node.maxItems then return false end
    if node.uniqueItems then
      for i = 2, #value do
        for j = 1, i - 1 do
          if equal(value[i], value[j]) then return false end
        end
      end
    end
    if node.items ~= nil then
      for i = 1, #value do
        if not conforms(node.items, value[i], root) then return false end
      end
    end
  end
  if kind == "object" or (kind == "empty" and node.type == "object") then
    for _, name in ipairs(node.required or {}) do
      if value[name] == nil then return false end
    end
    local count = 0
    for key, member in pairs(value) do
      count = count + 1
      local property = node.properties and node.properties[key]
      if property ~= nil then
        if not conforms(property, member, root) then return false end
      elseif node.additionalProperties ~= nil and not conforms(node.additionalProperties, member, root) then
        return false
      end
    end
    if node.minProperties and count < node.minProperties then return false end
    if node.maxProperties and count > node.maxProperties then return false end
  end
  return true
end

--- Tells whether `value` conforms to the JSON Schema document `emitted`.
---@param emitted table|boolean
---@param value any
---@return boolean
function M.conforms(emitted, value) return conforms(emitted, value, emitted) end

return M
