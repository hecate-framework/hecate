-- The pure-Lua reference backend of hecate.json.
--
-- Status: the fallback used when the native backend (`hecate.json.native`: yyjson decoder, serde_json
-- encoder, ADR 0020 and ADR 0021) is not built, and the oracle the native backend is tested against
-- (the same inputs must give the same values, the same JSON text and the same failure reasons).
-- It favours clarity over speed; it is the specification of the value model in executable form.
--
-- Backend contract (shared with the native backend, see `hecate.json.internal.backend`):
--   decode(text, options) -> value | nil, failure     options: { max_depth, max_size }
--   encode(value, options) -> text | nil, failure     options: { max_depth, max_size, indent?, canonical, rfc8785 }
-- `rfc8785` (implies `canonical`, never combined with `indent`) selects RFC 8785 (JCS): every number is
-- written as an IEEE double in the ECMAScript format, and an integer beyond +-2^53 is a failure.
-- A `failure` is { reason = <string>, message = <string>, offset = <integer> } for decoding (offset:
-- bytes before the offending byte) and { reason, message, path = <RFC 6901 pointer> } for encoding.
-- Options arrive validated and complete; the public module (`hecate.json`) owns validation, the
-- construction of error objects and the line and column of a decoding failure.
--
-- Normative behaviour implemented here, with its source:
--   RFC 8259 section 2 (whitespace), 3 (literals), 4 (objects), 5 (arrays), 6 (numbers), 7 (strings),
--   8.1 (UTF-8, no byte order mark), 8.2 (surrogate pairs); I-JSON (RFC 7493) sections 2.1 to 2.3
--   (well-formed UTF-8 and surrogates, no duplicate member names); RFC 6901 section 3 and 5 (the
--   pointer of an encoding failure).
global <const> require, type, next, rawget, rawlen, getmetatable, tostring, tonumber, error, pcall,
  string, table, math, utf8

local markers = require("hecate.json.internal.markers")

local byte, find, sub, format, rep, gsub, char = string.byte, string.find, string.sub, string.format, string.rep,
  string.gsub, string.char
local concat, sort = table.concat, table.sort
local mtype, huge = math.type, math.huge
local null, array_metatable, object_metatable = markers.null, markers.array_metatable, markers.object_metatable
local tag = markers.tag

local M = {}

-- A failure travels as an error carrying this metatable, so that `pcall` at the entry points tells
-- it apart from a genuine bug (which is rethrown untouched).
local FAILURE = {}

---@param reason string
---@param message string
---@param position integer|string  byte offset when decoding, JSON Pointer when encoding
local function fail(reason, message, position)
  error(tag({ reason = reason, message = message, position = position }, FAILURE), 0)
end

---@param ok boolean
---@param result any
---@param decoding boolean
local function settle(ok, result, decoding)
  if ok then return result end
  if getmetatable(result) ~= FAILURE then error(result, 0) end
  local failure = { reason = result.reason, message = result.message }
  if decoding then failure.offset = result.position else failure.path = result.position end
  return nil, failure
end

---------------------------------------------------------------------------------------------------
-- Decoder
---------------------------------------------------------------------------------------------------

local ESCAPES = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }

local function describe(text, pos)
  local c = byte(text, pos)
  if c == nil then return "end of input" end
  if c < 32 or c == 127 then return format("control character 0x%02x", c) end
  if c < 128 then return format("character '%s'", char(c)) end
  return format("byte 0x%02x", c)
end

-- Text that comes from the input and is echoed in a message (a member name, a number literal): at most
-- EXCERPT_LIMIT bytes, cut on a character boundary, with every control character, quote and backslash escaped, so
-- that a hostile text can neither grow the message nor forge a line of a log (no raw line feed).
local EXCERPT_LIMIT = 40

local function excerpt(text)
  local cut = #text > EXCERPT_LIMIT
  if cut then
    local stop = EXCERPT_LIMIT
    while stop > 0 and byte(text, stop + 1) and byte(text, stop + 1) >= 0x80 and byte(text, stop + 1) < 0xC0 do
      stop = stop - 1 -- do not cut inside a UTF-8 sequence
    end
    text = sub(text, 1, stop)
  end
  local shown = gsub(text, '[%c"\\\127]', function(c) return format("\\x%02x", byte(c)) end)
  return '"' .. shown .. '"' .. (cut and " (cut)" or "")
end

--- Decodes a JSON text.
---@param text string
---@param options { max_depth: integer, max_size: integer }
---@return any value
---@return { reason: string, message: string, offset: integer }? failure
function M.decode(text, options)
  local max_depth = options.max_depth
  local length = #text

  local function unexpected(pos, expected)
    fail("syntax", ("unexpected %s: expected %s"):format(describe(text, pos), expected), pos - 1)
  end

  local function skip_space(pos)
    local _, last = find(text, "^[ \t\n\r]*", pos)
    return last + 1
  end

  -- RFC 8259 section 7: a string is quoted; escapes are \" \\ \/ \b \f \n \r \t and \uXXXX; U+0000 to
  -- U+001F must be escaped. Section 8.2 and I-JSON section 2.1: a surrogate is valid only as half of a pair.
  local function parse_string(pos)
    local first = pos + 1
    local stop = find(text, '[\0-\31"\\]', first)
    if stop and byte(text, stop) == 34 then -- fast path: no escape, no control character
      local s = sub(text, first, stop - 1)
      if find(s, "[\128-\255]") then
        local ok, bad = utf8.len(s)
        if not ok then fail("invalid_utf8", "invalid UTF-8 in string", first + bad - 2) end
      end
      return s, stop + 1
    end
    local parts, count = {}, 0
    local i = first
    while true do
      stop = find(text, '[\0-\31"\\]', i)
      if stop == nil then fail("syntax", "unterminated string: expected a closing quote", length) end
      if stop > i then
        local s = sub(text, i, stop - 1)
        if find(s, "[\128-\255]") then
          local ok, bad = utf8.len(s)
          if not ok then fail("invalid_utf8", "invalid UTF-8 in string", i + bad - 2) end
        end
        count = count + 1
        parts[count] = s
      end
      local c = byte(text, stop)
      if c == 34 then return concat(parts), stop + 1 end
      if c < 32 then
        fail("control_character", ("unescaped %s in string"):format(describe(text, stop)), stop - 1)
      end
      local e = byte(text, stop + 1)
      local plain = ESCAPES[e]
      if plain then
        count = count + 1
        parts[count] = plain
        i = stop + 2
      elseif e == 117 then -- \u
        local hex = text:match("^%x%x%x%x", stop + 2)
        if hex == nil then fail("invalid_escape", "invalid \\u escape: expected four hexadecimal digits", stop - 1) end
        local code = tonumber(hex, 16)
        i = stop + 6
        if code >= 0xD800 and code <= 0xDBFF then
          local low = text:match("^\\u(%x%x%x%x)", i)
          local low_code = low and tonumber(low, 16)
          if low_code == nil or low_code < 0xDC00 or low_code > 0xDFFF then
            fail("lone_surrogate", "lone high surrogate escape: a \\uD800-\\uDBFF escape must be followed at once by a "
              .. "\\uDC00-\\uDFFF escape (RFC 8259 section 8.2); a lone surrogate is not a character and is rejected "
              .. "(I-JSON, RFC 7493 section 2.1)", stop - 1)
          end
          code = 0x10000 + ((code - 0xD800) << 10) + (low_code - 0xDC00)
          i = i + 6
        elseif code >= 0xDC00 and code <= 0xDFFF then
          fail("lone_surrogate", "lone low surrogate escape: a \\uDC00-\\uDFFF escape must follow a \\uD800-\\uDBFF "
            .. "escape (RFC 8259 section 8.2); a lone surrogate is not a character and is rejected "
            .. "(I-JSON, RFC 7493 section 2.1)", stop - 1)
        end
        count = count + 1
        parts[count] = utf8.char(code)
      else
        fail("invalid_escape", ("invalid escape: unexpected %s after backslash"):format(describe(text, stop + 1)), stop - 1)
      end
    end
  end

  -- RFC 8259 section 6: -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?. A number with a fraction
  -- or an exponent is a float, any other is an integer when it fits in 64 bits, else a float.
  local function parse_number(pos)
    local p = pos
    if byte(text, p) == 45 then p = p + 1 end
    local c = byte(text, p)
    if c == 48 then
      p = p + 1
      local d = byte(text, p)
      if d and d >= 48 and d <= 57 then fail("syntax", "invalid number: leading zeros are not allowed", p - 1) end
    elseif c and c >= 49 and c <= 57 then
      local _, last = find(text, "^%d*", p + 1)
      p = last + 1
    else
      unexpected(p, "a digit")
    end
    local is_float = false
    if byte(text, p) == 46 then
      local _, last = find(text, "^%d+", p + 1)
      if last == nil then unexpected(p + 1, "a digit after the decimal point") end
      p = last + 1
      is_float = true
    end
    c = byte(text, p)
    if c == 101 or c == 69 then
      p = p + 1
      c = byte(text, p)
      if c == 43 or c == 45 then p = p + 1 end
      local _, last = find(text, "^%d+", p)
      if last == nil then unexpected(p, "a digit in the exponent") end
      p = last + 1
      is_float = true
    end
    local literal = sub(text, pos, p - 1)
    -- "-0" is an integer literal: it decodes as the integer 0 (an integer has no sign); "-0.0" and
    -- "-0e0" are floats and keep their sign.
    local value = tonumber(literal)
    if is_float and mtype(value) ~= "float" then value = value + 0.0 end
    if value == huge or value == -huge then
      fail("number_out_of_range", ("number %s is out of range: it does not fit in a 64-bit float (about 1.8e308 at most); "
        .. "RFC 8259 allows it but parsers disagree on the result (infinity, error or clamp), so it is rejected"):format(
        excerpt(literal)), pos - 1)
    end
    return value, p
  end

  local parse_value

  -- RFC 8259 section 5.
  local function parse_array(pos, depth)
    if depth > max_depth then
      fail("depth_limit", ("nesting deeper than max_depth (%d)"):format(max_depth), pos - 1)
    end
    local result, count = tag({}, array_metatable), 0
    pos = skip_space(pos + 1)
    if byte(text, pos) == 93 then return result, pos + 1 end
    while true do
      local value
      value, pos = parse_value(pos, depth)
      count = count + 1
      result[count] = value
      pos = skip_space(pos)
      local c = byte(text, pos)
      if c == 44 then
        pos = skip_space(pos + 1)
      elseif c == 93 then
        return result, pos + 1
      else
        unexpected(pos, "',' or ']'")
      end
    end
  end

  -- RFC 8259 section 4; duplicate member names are rejected (section 4: "SHOULD be unique", I-JSON 2.3).
  local function parse_object(pos, depth)
    if depth > max_depth then
      fail("depth_limit", ("nesting deeper than max_depth (%d)"):format(max_depth), pos - 1)
    end
    local result = tag({}, object_metatable)
    pos = skip_space(pos + 1)
    if byte(text, pos) == 125 then return result, pos + 1 end
    while true do
      if byte(text, pos) ~= 34 then unexpected(pos, "a string (member name)") end
      local key_at = pos
      local key
      key, pos = parse_string(pos)
      if rawget(result, key) ~= nil then
        fail("duplicate_key", ("duplicate member name %s: RFC 8259 allows it but parsers disagree on which value wins, "
          .. "so it is rejected (I-JSON, RFC 7493 section 2.3)"):format(excerpt(key)), key_at - 1)
      end
      pos = skip_space(pos)
      if byte(text, pos) ~= 58 then unexpected(pos, "':'") end
      pos = skip_space(pos + 1)
      local value
      value, pos = parse_value(pos, depth)
      result[key] = value
      pos = skip_space(pos)
      local c = byte(text, pos)
      if c == 44 then
        pos = skip_space(pos + 1)
      elseif c == 125 then
        return result, pos + 1
      else
        unexpected(pos, "',' or '}'")
      end
    end
  end

  function parse_value(pos, depth)
    local c = byte(text, pos)
    if c == 34 then return parse_string(pos) end
    if c == 123 then return parse_object(pos, depth + 1) end
    if c == 91 then return parse_array(pos, depth + 1) end
    if c == 45 or (c and c >= 48 and c <= 57) then return parse_number(pos) end
    if c == 116 and sub(text, pos, pos + 3) == "true" then return true, pos + 4 end
    if c == 102 and sub(text, pos, pos + 4) == "false" then return false, pos + 5 end
    if c == 110 and sub(text, pos, pos + 3) == "null" then return null, pos + 4 end
    unexpected(pos, "a value")
  end

  local function run()
    if length > options.max_size then
      fail("size_limit", ("input of %d bytes exceeds max_size (%d)"):format(length, options.max_size), 0)
    end
    if sub(text, 1, 3) == "\239\187\191" then
      fail("byte_order_mark", "the text starts with a byte order mark: RFC 8259 section 8.1 lets a parser ignore it but "
        .. "parsers disagree, so it is rejected; strip the first three bytes (EF BB BF) before decoding", 0)
    end
    local pos = skip_space(1)
    local value
    value, pos = parse_value(pos, 0)
    pos = skip_space(pos)
    if pos <= length then unexpected(pos, "end of input") end
    return value
  end

  local ok, result = pcall(run)
  return settle(ok, result, true)
end

---------------------------------------------------------------------------------------------------
-- Encoder
---------------------------------------------------------------------------------------------------

local STRING_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
  ["\r"] = "\\r", ["\t"] = "\\t" }
for code = 0, 31 do
  local c = char(code)
  if STRING_ESCAPES[c] == nil then STRING_ESCAPES[c] = format("\\u%04x", code) end
end

-- RFC 6901 section 3 and 5: "~" is written "~0" and "/" is written "~1" in a reference token.
-- RFC 8785 section 3.2.3: member names sort by their UTF-16 code units. The byte order of UTF-8 is the
-- order of code points, which differs only for a character beyond U+FFFF (a surrogate pair, D800-DFFF
-- in UTF-16) against one in U+E000-U+FFFF. Rewriting each beyond-BMP character as its two surrogates
-- (CESU-8) makes the byte order equal the UTF-16 order. String comparison with `<` is byte-wise in
-- the C locale, which Lua keeps unless the host calls os.setlocale.
local function utf16_order_key(name)
  return (gsub(name, "[\240-\244][\128-\191][\128-\191][\128-\191]", function(sequence)
    -- An overlong form or a value beyond U+10FFFF matches the pattern but is not UTF-8: leave it, the encoder
    -- rejects the member name with `invalid_utf8` when it writes it.
    local ok, point = pcall(utf8.codepoint, sequence)
    if not ok then return sequence end
    local code = point - 0x10000
    return utf8.char(0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF))
  end))
end

---@param names string[]
local function sort_names(names)
  local astral = false
  for i = 1, #names do
    if find(names[i], "[\240-\244]") then astral = true break end
  end
  if not astral then sort(names) return end
  local order = {}
  for i = 1, #names do order[names[i]] = utf16_order_key(names[i]) end
  sort(names, function(a, b) return order[a] < order[b] end)
end

-- RFC 8785 section 3.2.2.3 (via ECMAScript Number::toString): the shortest digits that read back as the same
-- double, laid out as digits, a decimal point or an exponent depending on the magnitude. Negative zero is "0".
local MAX_SAFE = 9007199254740992 -- 2^53

---@param number number  a finite float
---@return string
local function es_number(number)
  if number == 0 then return "0" end
  local sign = ""
  if number < 0 then sign, number = "-", -number end
  local mantissa, exponent
  for precision = 0, 16 do -- the first precision that reads back is the shortest
    local text = format("%." .. precision .. "e", number)
    if tonumber(text) == number or precision == 16 then
      mantissa, exponent = text:match("^([%d.]+)e([+-]%d+)$")
      break
    end
  end
  local digits = gsub(mantissa, "%.", "")
  digits = gsub(digits, "0+$", "")
  if digits == "" then digits = "0" end
  local k = #digits
  local n = tonumber(exponent) + 1 -- value = 0.DIGITS * 10^n
  local body
  if k <= n and n <= 21 then
    body = digits .. rep("0", n - k)
  elseif 0 < n and n <= 21 then
    body = sub(digits, 1, n) .. "." .. sub(digits, n + 1)
  elseif -6 < n and n <= 0 then
    body = "0." .. rep("0", -n) .. digits
  else
    local e = n - 1
    local tail = (e < 0 and "-" or "+") .. tostring(e < 0 and -e or e)
    body = (k == 1 and digits or (sub(digits, 1, 1) .. "." .. sub(digits, 2))) .. "e" .. tail
  end
  return sign .. body
end

local function escape_token(token) return (gsub(gsub(token, "~", "~0"), "/", "~1")) end

--- Encodes a value as JSON text.
---@param value any
---@param options { max_depth: integer, max_size: integer, indent?: string, canonical: boolean, rfc8785: boolean }
---@return string? text
---@return { reason: string, message: string, path: string }? failure
function M.encode(value, options)
  local max_depth, max_size, indent, canonical = options.max_depth, options.max_size, options.indent, options.canonical
  local rfc8785 = options.rfc8785
  local buffer, count, size = {}, 0, 0
  local trail = {} -- trail[d]: the key (string) or index (integer, 1-based) taken at depth d

  local function pointer(depth)
    local tokens = {}
    for d = 1, depth do
      local step = trail[d]
      tokens[d] = type(step) == "string" and escape_token(step) or tostring(step - 1)
    end
    return depth == 0 and "" or ("/" .. concat(tokens, "/"))
  end

  local function reject(reason, message, depth) fail(reason, message, pointer(depth)) end

  local function emit(piece)
    count = count + 1
    buffer[count] = piece
    size = size + #piece
    if size > max_size then
      fail("size_limit", ("output exceeds max_size (%d bytes)"):format(max_size), "")
    end
  end

  -- RFC 8259 section 7 (escaping) and 8.1 (UTF-8): the output is always well-formed UTF-8, so a
  -- string that is not is rejected rather than repaired.
  local function emit_string(s, depth)
    if find(s, '[\0-\31"\\\128-\255]') then
      if find(s, "[\128-\255]") and not utf8.len(s) then
        reject("invalid_utf8", "string is not valid UTF-8", depth)
      end
      s = gsub(s, '[\0-\31"\\]', STRING_ESCAPES)
    end
    emit('"')
    emit(s)
    emit('"')
  end

  -- RFC 8259 section 6: NaN and the infinities are not numbers of the grammar. A float is written
  -- with the fewest digits (15 to 17) that read back as the same float, and always with a decimal
  -- point or an exponent, so that it decodes as a float again (the fidelity rule of ADR 0020).
  local function emit_float(number, depth)
    if number ~= number or number == huge or number == -huge then
      reject("non_finite_number", ("%s is not a JSON number"):format(tostring(number)), depth)
    end
    if rfc8785 then emit(es_number(number)) return end
    local text = format("%.15g", number)
    if tonumber(text) ~= number then
      text = format("%.16g", number)
      if tonumber(text) ~= number then text = format("%.17g", number) end
    end
    if not find(text, "[.eE]") then text = text .. ".0" end
    emit(text)
  end

  -- The length of a table written as an array: its highest index. A hole (an index of 1..n without
  -- a value) is written as null, since a Lua `nil` stands for the absence of a value; holes are
  -- accepted while the table stays dense enough (n <= 2 * entries + 16), so that a stray `t[1e9] = x`
  -- cannot make the encoder write a billion nulls. Returns nil when a key is not a positive index
  -- or the table is too sparse.
  local function array_length(t)
    local entries, highest = 0, 0
    for key in next, t do
      if mtype(key) ~= "integer" or key < 1 then return nil end
      entries = entries + 1
      if key > highest then highest = key end
    end
    if highest > 2 * entries + 16 then return nil end
    return highest
  end

  -- An unmarked table is an array when its keys are all positive indices (see array_length), an
  -- object when all keys are strings, and an object when it is empty (the documented rule, see
  -- README); anything else is ambiguous.
  local function classify(t, depth)
    local string_keys = true
    for key in next, t do
      if type(key) ~= "string" then string_keys = false break end
    end
    if string_keys then return "object" end
    if array_length(t) then return "array" end
    reject("ambiguous_table",
      "table is neither a sequence nor an object with string keys: mark it with json.array or json.object", depth)
  end

  local emit_value

  local function emit_array(t, depth)
    local length = array_length(t)
    if length == nil then
      reject("sparse_array",
        "array has a key that is not a positive index, or too many holes (a hole is written as null while the "
          .. "highest index is at most twice the number of entries plus 16)", depth - 1)
    end
    if length == 0 then emit("[]") return end
    emit("[")
    for i = 1, length do
      if i > 1 then emit(",") end
      if indent then emit("\n" .. rep(indent, depth)) end
      trail[depth] = i
      local element = rawget(t, i)
      if element == nil then emit("null") else emit_value(element, depth) end
    end
    if indent then emit("\n" .. rep(indent, depth - 1)) end
    emit("]")
  end

  local function emit_object(t, depth)
    local keys, n = {}, 0
    for key in next, t do
      if type(key) ~= "string" then
        reject("ambiguous_table", ("object keys must be strings, got a key of type %s"):format(
          mtype(key) or type(key)), depth - 1)
      end
      n = n + 1
      keys[n] = key
    end
    if n == 0 then emit("{}") return end
    if canonical then sort_names(keys) end
    emit("{")
    for i = 1, n do
      local key = keys[i]
      if i > 1 then emit(",") end
      if indent then emit("\n" .. rep(indent, depth)) end
      trail[depth] = key
      emit_string(key, depth)
      emit(indent and ": " or ":")
      emit_value(rawget(t, key), depth)
    end
    if indent then emit("\n" .. rep(indent, depth - 1)) end
    emit("}")
  end

  -- `depth` is the nesting level of the container holding `v` (0 for the top-level value); the
  -- path to `v` is trail[1..depth].
  function emit_value(v, depth)
    local kind = type(v)
    if kind == "string" then
      emit_string(v, depth)
    elseif kind == "number" then
      if mtype(v) ~= "integer" then
        emit_float(v, depth)
      elseif rfc8785 then
        if v > MAX_SAFE or v < -MAX_SAFE then
          reject("integer_out_of_range", ("integer %d is beyond +-2^53: RFC 8785 writes numbers as IEEE doubles, "
            .. "which would silently change it; write it as a string"):format(v), depth)
        end
        emit(es_number(v + 0.0))
      else
        emit(format("%d", v))
      end
    elseif kind == "boolean" then
      emit(v and "true" or "false")
    elseif v == null then
      emit("null")
    elseif kind == "table" then
      local level = depth + 1
      if level > max_depth then
        reject("depth_limit", ("nesting deeper than max_depth (%d)"):format(max_depth), depth)
      end
      local metatable = getmetatable(v)
      local shape
      if metatable == array_metatable then
        shape = "array"
      elseif metatable == object_metatable then
        shape = "object"
      else
        shape = classify(v, depth)
      end
      if shape == "array" then emit_array(v, level) else emit_object(v, level) end
    else
      reject("unsupported_type", ("a value of type %s has no JSON representation"):format(kind), depth)
    end
  end

  local function run()
    emit_value(value, 0)
    return concat(buffer)
  end

  local ok, result = pcall(run)
  return settle(ok, result, false)
end

return M
