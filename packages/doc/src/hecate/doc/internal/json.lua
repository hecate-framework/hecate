-- A small JSON codec (RFC 8259) for the search index, the page configuration and the LuaLS
-- export. The encoder is deterministic: object keys are sorted, so the output is stable. The
-- decoder is a strict recursive-descent parser. Both exist because `hecate.json` has no
-- implementation yet (OQ-33, OQ-40); the package should switch to it then.
-- `<`, `>` and `&` are written as `<`, `>`, `&`, so the output can also be
-- placed inside an HTML `<script>` element without being able to close it.
global <const> type, pairs, ipairs, table, string, math, error, tostring, utf8, tonumber

local M = {}

--- Stands for a JSON `null` inside an array, so that the array keeps its length. A `null`
--- object member is omitted and a top-level `null` decodes to `nil`.
M.null = {}

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

-- Decoding ----------------------------------------------------------------------------

local MAX_DEPTH = 200

local function fail(source, position, message)
  local line = 1
  for _ in source:sub(1, position - 1):gmatch("\n") do line = line + 1 end
  error(("invalid JSON at byte %d (line %d): %s"):format(position, line, message), 0)
end

local function skip(source, position)
  return source:find("[^ \t\r\n]", position) or #source + 1
end

local SIMPLE = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function parse_string(source, position)
  local parts, start = {}, position + 1
  while true do
    local stop = source:find('["\\%c]', start)
    if not stop then fail(source, position, "unterminated string") end
    local char = source:sub(stop, stop)
    parts[#parts + 1] = source:sub(start, stop - 1)
    if char == '"' then return table.concat(parts), stop + 1 end
    if char ~= "\\" then fail(source, stop, "control character in string") end
    local escape = source:sub(stop + 1, stop + 1)
    if escape == "u" then
      local hex = source:match("^%x%x%x%x", stop + 2)
      if not hex then fail(source, stop, "bad \\u escape") end
      local code = tonumber(hex, 16)
      start = stop + 6
      if code >= 0xD800 and code <= 0xDBFF then
        local low = source:match("^\\u(%x%x%x%x)", start)
        local low_code = low and tonumber(low, 16)
        if not low_code or low_code < 0xDC00 or low_code > 0xDFFF then
          fail(source, stop, "unpaired surrogate")
        end
        code = 0x10000 + (code - 0xD800) * 0x400 + (low_code - 0xDC00)
        start = start + 6
      elseif code >= 0xDC00 and code <= 0xDFFF then
        fail(source, stop, "unpaired surrogate")
      end
      parts[#parts + 1] = utf8.char(code)
    else
      local simple = SIMPLE[escape]
      if not simple then fail(source, stop, "bad escape \\" .. escape) end
      parts[#parts + 1] = simple
      start = stop + 2
    end
  end
end

local parse_value

local function parse_array(source, position, depth)
  local list = {}
  position = skip(source, position + 1)
  if source:sub(position, position) == "]" then return list, position + 1 end
  while true do
    local value
    value, position = parse_value(source, position, depth + 1)
    if value == nil then value = M.null end
    list[#list + 1] = value
    position = skip(source, position)
    local char = source:sub(position, position)
    if char == "]" then return list, position + 1 end
    if char ~= "," then fail(source, position, "expected , or ]") end
    position = skip(source, position + 1)
  end
end

local function parse_object(source, position, depth)
  local object = {}
  position = skip(source, position + 1)
  if source:sub(position, position) == "}" then return object, position + 1 end
  while true do
    if source:sub(position, position) ~= '"' then fail(source, position, "expected a string key") end
    local key
    key, position = parse_string(source, position)
    position = skip(source, position)
    if source:sub(position, position) ~= ":" then fail(source, position, "expected :") end
    local value
    value, position = parse_value(source, skip(source, position + 1), depth + 1)
    object[key] = value
    position = skip(source, position)
    local char = source:sub(position, position)
    if char == "}" then return object, position + 1 end
    if char ~= "," then fail(source, position, "expected , or }") end
    position = skip(source, position + 1)
  end
end

parse_value = function(source, position, depth)
  if depth > MAX_DEPTH then fail(source, position, "nesting too deep") end
  local char = source:sub(position, position)
  if char == "{" then return parse_object(source, position, depth) end
  if char == "[" then return parse_array(source, position, depth) end
  if char == '"' then return parse_string(source, position) end
  if char == "-" or char:find("^%d") then
    -- RFC 8259, section 6: int [ frac ] [ exp ], no leading zeros.
    local integer = source:match("^-?%d+", position)
    if not integer or integer:find("^-?0%d") then fail(source, position, "bad number") end
    local stop = position + #integer
    local fraction = source:match("^%.%d+", stop)
    if source:sub(stop, stop) == "." and not fraction then fail(source, stop, "bad number") end
    stop = stop + (fraction and #fraction or 0)
    local exponent = source:match("^[eE][-+]?%d+", stop)
    if source:find("^[eE]", stop) and not exponent then fail(source, stop, "bad number") end
    stop = stop + (exponent and #exponent or 0)
    local text = source:sub(position, stop - 1)
    if not fraction and not exponent then
      return math.tointeger(tonumber(text)) or tonumber(text), stop
    end
    return tonumber(text) + 0.0, stop
  end
  if source:sub(position, position + 3) == "true" then return true, position + 4 end
  if source:sub(position, position + 4) == "false" then return false, position + 5 end
  if source:sub(position, position + 3) == "null" then return nil, position + 4 end
  fail(source, position, "unexpected " .. (char == "" and "end of input" or char))
end

--- Decodes one JSON text (RFC 8259). Integers without fraction or exponent decode to Lua
--- integers, other numbers to floats; `null` decodes to `nil` (see `json.null` for arrays).
--- Raises a string error `invalid JSON at byte N (line L): ...` for malformed input or
--- nesting deeper than 200 levels.
---@param source string  the JSON text, UTF-8
---@return any value
function M.decode(source)
  local position = skip(source, 1)
  local value, stop = parse_value(source, position, 1)
  stop = skip(source, stop)
  if stop <= #source then fail(source, stop, "unexpected content after the value") end
  return value
end

return M
