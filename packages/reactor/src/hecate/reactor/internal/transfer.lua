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

  -- The path of the value being encoded, kept as a stack of keys: the label of an error message
  -- ("argument 2.list[3]") is built only when an error is raised, never on the normal path.
  local path, path_length, prefix = {}, 0, ""

  local function fail(reason)
    local parts = { prefix }
    for i = 1, path_length do
      local key = path[i]
      parts[#parts + 1] = type(key) == "string" and ("." .. key) or ("[" .. tostring(key) .. "]")
    end
    error(table.concat(parts) .. ": " .. reason, 0)
  end

  local encode_value

  local function encode_table(buffer, size, value, depth, seen)
    if getmetatable(value) ~= nil then fail("a table with a metatable cannot cross between Lua states") end
    if seen[value] then fail("a table that contains itself cannot cross between Lua states") end
    if depth > MAX_DEPTH then
      fail(("tables nested deeper than %d levels cannot cross between Lua states"):format(MAX_DEPTH))
    end
    seen[value] = true
    size = size + 1
    buffer[size] = "T"
    size = size + 1
    local slot = size
    buffer[slot] = "" -- the count of pairs, written after the loop
    local count = 0
    path_length = path_length + 1
    local key, item = next(value)
    while key ~= nil do
      path[path_length] = key
      local kind = type(key)
      if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        fail(("a key of type %s cannot cross between Lua states"):format(kind))
      end
      size = encode_value(buffer, size, key, depth + 1, seen)
      size = encode_value(buffer, size, item, depth + 1, seen)
      count = count + 1
      key, item = next(value, key)
    end
    path[path_length] = nil
    path_length = path_length - 1
    buffer[slot] = pack("<j", count)
    seen[value] = nil
    return size
  end

  --- Appends the encoding of `value` after `buffer[size]`; returns the new size.
  function encode_value(buffer, size, value, depth, seen)
    local kind = type(value)
    if value == nil then
      buffer[size + 1] = "n"
    elseif value == true then
      buffer[size + 1] = "t"
    elseif value == false then
      buffer[size + 1] = "f"
    elseif kind == "number" then
      if math.type(value) == "integer" then
        buffer[size + 1] = pack("<c1j", "i", value)
      else
        buffer[size + 1] = pack("<c1n", "d", value)
      end
    elseif kind == "string" then
      buffer[size + 1] = pack("<c1s8", "s", value)
    elseif kind == "table" then
      return encode_table(buffer, size, value, depth, seen)
    else
      fail(("a %s cannot cross between Lua states"):format(kind))
    end
    return size + 1
  end

  --- Encodes `values[first .. first + n - 1]`; `label` names them in messages ("argument").
  local function encode(label, n, values, first)
    first = first or 1
    local buffer, size = { pack("<j", n) }, 1
    path_length = 0
    for i = 1, n do
      prefix = label .. " " .. i
      size = encode_value(buffer, size, values[first + i - 1], 1, {})
    end
    return table.concat(buffer, "", 1, size)
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
