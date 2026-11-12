-- Copies values between two Lua states as a byte string, for `reactor.offload` (concurrency.md,
-- "Offload"). The same code runs on the reactor thread and on the pool threads: `factory` has no
-- upvalue but `_ENV`, so it can be sent as bytecode (`code`) and loaded in a state that cannot
-- `require` this module. Not public API.
--
-- Encoding: a count of values (`<j`), then each value as a one-byte tag and its payload: `n` nil,
-- `f` false, `t` true, `i` integer (`<j`), `d` float (`<n`), `s` string (`<s8`), `T` plain table
-- (a count of pairs, then key and value for each pair).
global <const> string, type, math, next, getmetatable, error, tostring, table

---@class hecate.reactor.internal.Codec
---@field encode fun(label: string, n: integer, values: table, first?: integer): string
---@field decode fun(data: string): integer, table

--- Builds the codec. Self-contained on purpose (see the file header): every helper is local.
---@return hecate.reactor.internal.Codec
local function factory()
  local pack, unpack = string.pack, string.unpack
  local MAX_DEPTH = 100

  local function describe(value)
    local kind = type(value)
    if kind == "table" then return "a table with a metatable" end
    return "a " .. kind
  end

  local encode_value

  local function encode_table(buffer, value, depth, seen, where)
    if getmetatable(value) ~= nil then
      error(where .. ": a table with a metatable cannot cross between Lua states", 0)
    end
    if seen[value] then error(where .. ": a table that contains itself cannot cross between Lua states", 0) end
    if depth > MAX_DEPTH then
      error(where .. (": tables nested deeper than %d levels cannot cross between Lua states"):format(MAX_DEPTH), 0)
    end
    seen[value] = true
    buffer[#buffer + 1] = "T"
    local slot = #buffer + 1
    buffer[slot] = "" -- the count of pairs, written after the loop
    local count = 0
    local key, item = next(value)
    while key ~= nil do
      local kind = type(key)
      if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        error(("%s: a key of type %s cannot cross between Lua states"):format(where, kind), 0)
      end
      local label = kind == "string" and (where .. "." .. key) or (where .. "[" .. tostring(key) .. "]")
      encode_value(buffer, key, depth + 1, seen, label)
      encode_value(buffer, item, depth + 1, seen, label)
      count = count + 1
      key, item = next(value, key)
    end
    buffer[slot] = pack("<j", count)
    seen[value] = nil
  end

  function encode_value(buffer, value, depth, seen, where)
    local kind = type(value)
    if value == nil then
      buffer[#buffer + 1] = "n"
    elseif value == true then
      buffer[#buffer + 1] = "t"
    elseif value == false then
      buffer[#buffer + 1] = "f"
    elseif kind == "number" then
      if math.type(value) == "integer" then
        buffer[#buffer + 1] = "i" .. pack("<j", value)
      else
        buffer[#buffer + 1] = "d" .. pack("<n", value)
      end
    elseif kind == "string" then
      buffer[#buffer + 1] = "s" .. pack("<s8", value)
    elseif kind == "table" then
      encode_table(buffer, value, depth, seen, where)
    else
      error(("%s: %s cannot cross between Lua states"):format(where, describe(value)), 0)
    end
  end

  --- Encodes `values[first .. first + n - 1]`; `label` names them in messages ("argument").
  local function encode(label, n, values, first)
    first = first or 1
    local buffer = { pack("<j", n) }
    for i = 1, n do
      encode_value(buffer, values[first + i - 1], 1, {}, label .. " " .. i)
    end
    return table.concat(buffer)
  end

  local decode_value

  local function decode_table(data, position)
    local count
    count, position = unpack("<j", data, position)
    local result = {}
    for _ = 1, count do
      local key, item
      key, position = decode_value(data, position)
      item, position = decode_value(data, position)
      result[key] = item
    end
    return result, position
  end

  function decode_value(data, position)
    local tag = data:sub(position, position)
    position = position + 1
    if tag == "n" then return nil, position end
    if tag == "t" then return true, position end
    if tag == "f" then return false, position end
    if tag == "i" then return unpack("<j", data, position) end
    if tag == "d" then return unpack("<n", data, position) end
    if tag == "s" then return unpack("<s8", data, position) end
    if tag == "T" then return decode_table(data, position) end
    error(("malformed transfer encoding at byte %d"):format(position - 1), 0)
  end

  --- Decodes a string built by `encode`: returns the count and the values (holes kept).
  local function decode(data)
    local n, position = unpack("<j", data)
    local values = {}
    for i = 1, n do
      values[i], position = decode_value(data, position)
    end
    return n, values
  end

  return { encode = encode, decode = decode }
end

---@class hecate.reactor.internal.Transfer
---@field factory fun(): hecate.reactor.internal.Codec
---@field code string
---@field codec hecate.reactor.internal.Codec

---@type hecate.reactor.internal.Transfer
return {
  factory = factory,
  --- The bytecode of `factory`, loaded once per pool thread.
  code = string.dump(factory, true),
  codec = factory(),
}
