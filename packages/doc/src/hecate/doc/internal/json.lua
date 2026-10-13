-- A small deterministic JSON encoder (RFC 8259) for the search index and the page
-- configuration: object keys are sorted, so the output is stable. It exists because
-- `hecate.json` has no implementation yet (OQ-33); the builder should switch to it then.
-- `<`, `>` and `&` are written as `<`, `>`, `&`, so the output can also be
-- placed inside an HTML `<script>` element without being able to close it.
global <const> type, pairs, ipairs, table, string, math, error, tostring

local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
  ["\t"] = "\\t", ["<"] = "\\u003c", [">"] = "\\u003e", ["&"] = "\\u0026",
}

local function encode_string(value)
  return '"' .. value:gsub('[%c"\\<>&]', function(char)
    return ESCAPES[char] or ("\\u%04x"):format(char:byte())
  end) .. '"'
end

local function is_array(value)
  local count = 0
  for key in pairs(value) do
    if math.type(key) ~= "integer" or key < 1 then return false end
    count = count + 1
  end
  return count == #value
end

local function encode(value, out)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = encode_string(value)
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode a non-finite number", 0)
    end
    out[#out + 1] = math.type(value) == "integer" and tostring(value) or ("%.14g"):format(value)
  elseif kind == "boolean" then
    out[#out + 1] = value and "true" or "false"
  elseif kind == "table" then
    if is_array(value) then
      out[#out + 1] = "["
      for index, item in ipairs(value) do
        if index > 1 then out[#out + 1] = "," end
        encode(item, out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for key in pairs(value) do
        if type(key) ~= "string" then error("cannot encode a table with non-string keys", 0) end
        keys[#keys + 1] = key
      end
      table.sort(keys)
      out[#out + 1] = "{"
      for index, key in ipairs(keys) do
        if index > 1 then out[#out + 1] = "," end
        out[#out + 1] = encode_string(key) .. ":"
        encode(value[key], out)
      end
      out[#out + 1] = "}"
    end
  else
    error("cannot encode a " .. kind, 0)
  end
end

--- Encodes a Lua value as JSON. Tables with consecutive integer keys are arrays, others
--- objects with sorted keys; `nil` fields are omitted.
---@param value any
---@return string
function M.encode(value)
  local out = {}
  encode(value, out)
  return table.concat(out)
end

return M
