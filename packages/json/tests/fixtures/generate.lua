-- Generates the expected-output fixtures of the codec from the pure-Lua reference backend, the oracle that
-- OQ-53 retires. Run once, before `internal/reference.lua` is deleted:
--
--   LUA_PATH="packages/core/src/?.lua;packages/core/src/?/init.lua;packages/json/src/?.lua;packages/json/src/?/init.lua;;" \
--   LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;.hecate/rocks/lib/lua/5.5/?.so;;" lua packages/json/tests/fixtures/generate.lua
--
-- It writes `decode_cases.lua`, `encode_cases.lua` and `jcs_numbers.lua` next to this file. The files are the
-- oracle from then on: they are edited by hand where the behaviour is changed on purpose and never regenerated
-- (the generator is removed with the reference backend; the git history keeps both). Edited after generation: the message
-- of a NaN says `nan` whatever its sign (the sign of 0/0 differs between processors), and the `-0` decode cases.
local root = (arg[0]:match("^(.*)/tests/fixtures/[^/]*$") or ".")

local reference = require("hecate.json.internal.reference")
local native = require("hecate.json.native")
local markers = require("hecate.json.internal.markers")
local json = require("hecate.json")
local compatible = assert(loadfile(root .. "/tests/suites/failure.lua"))()

local array, object, null = json.array, json.object, json.null
local nan, inf = 0 / 0, math.huge
local DECODE_OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024 }
local ENCODE_OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = false, rfc8785 = false }

---------------------------------------------------------------------------------------------------
-- Writing Lua source
---------------------------------------------------------------------------------------------------

local function quote(s)
  local out = s:gsub('[%c"\\\127-\255]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    return ("\\%03d"):format(c:byte())
  end)
  return '"' .. out .. '"'
end

-- Unicode text stays readable: valid UTF-8 above 127 is written as it is.
local function quote_text(s)
  if utf8.len(s) == nil then return quote(s) end
  local out = s:gsub('[%c"\\\127]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    return ("\\%03d"):format(c:byte())
  end)
  return '"' .. out .. '"'
end

local function number(v)
  if math.type(v) == "integer" then
    if v == math.mininteger then return "math.mininteger" end
    return ("%d"):format(v)
  end
  if v ~= v then return "nan" end
  if v == math.huge then return "inf" end
  if v == -math.huge then return "-inf" end
  if v == 0 then return (1 / v < 0) and "-0.0" or "0.0" end
  local short = ("%.17g"):format(v)
  if tonumber(short) == v and not short:find("[eEn]") then
    return short:find("%.") and short or short .. ".0"
  end
  return ("%a"):format(v)
end

local serialize

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  return keys
end

-- A Lua expression that builds `v` again (markers, holes, floats bit for bit).
function serialize(v)
  local kind = type(v)
  if kind == "number" then return number(v) end
  if kind == "string" then return quote_text(v) end
  if kind == "boolean" then return tostring(v) end
  if v == null then return "null" end
  local metatable = getmetatable(v)
  local open, close = "{", "}"
  if metatable == markers.array_metatable then open, close = "array{", "}" end
  if metatable == markers.object_metatable then open, close = "object{", "}" end
  local parts = {}
  local keys = sorted_keys(v)
  local dense = true
  for i, k in ipairs(keys) do if k ~= i then dense = false break end end
  for _, k in ipairs(keys) do
    local item = serialize(v[k])
    if dense then parts[#parts + 1] = item
    elseif type(k) == "string" then parts[#parts + 1] = ("[%s] = %s"):format(quote_text(k), item)
    else parts[#parts + 1] = ("[%s] = %s"):format(number(k), item) end
  end
  return open .. table.concat(parts, ", ") .. close
end

local HEADER = [[
-- Expected outputs of the codec, generated from the pure-Lua reference backend before it was removed (OQ-53).
-- Edited by hand where the behaviour changed on purpose (see packages/json/README.md, "Known limitations").
]]

local VALUE_HEADER = [[
local json = require("hecate.json")
local array, object, null = json.array, json.object, json.null
local nan, inf = 0 / 0, math.huge
]]

local function write(name, header, entries)
  local file = assert(io.open(root .. "/tests/fixtures/" .. name, "wb"))
  file:write(HEADER, header, "\nreturn {\n")
  for _, entry in ipairs(entries) do file:write("  ", entry, ",\n") end
  file:write("}\n")
  file:close()
  print(("%s: %d entries"):format(name, #entries))
end

---------------------------------------------------------------------------------------------------
-- Decoding
---------------------------------------------------------------------------------------------------

local function canonical_text(value)
  local text, failure = reference.encode(value, { max_depth = 1000, max_size = 64 * 1024 * 1024, canonical = true, rfc8785 = false })
  assert(text, failure and failure.message)
  return text
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) == "number" then
    if math.type(a) ~= math.type(b) then return false end
    if a ~= a then return b ~= b end
    return a == b and (a ~= 0 or 1 / a == 1 / b or math.type(a) == "integer")
  end
  if type(a) ~= "table" then return a == b end
  if a == b then return true end
  if getmetatable(a) ~= getmetatable(b) then return false end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Texts whose expected value changes on purpose: yyjson reads the integer literal `-0` as the float -0.0 and nothing
-- can tell the two apart (OQ-53, owner decision of 2026-10-25). The reference decoder says the integer 0.
local NEGATIVE_ZERO = {
  ["-0"] = "-0.0", ["[-0, -0.0, 0, 0.0]"] = "[-0.0,-0.0,0,0.0]", ["-0e0"] = "-0.0", ["-0.0"] = "-0.0",
}

local decode_entries, seen, mismatches = {}, {}, 0

local function options_source(options)
  if options == nil then return "" end
  local keys = sorted_keys(options)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = ("%s = %d"):format(k, options[k]) end
  return (", options = { %s }"):format(table.concat(parts, ", "))
end

--- `strict`: the text has a single defect, so the offsets of the two decoders are compared too.
local function decode_case(text, options, strict)
  local key = text .. "\0" .. (options and (options.max_depth .. "," .. options.max_size) or "")
  if seen[key] then return end
  seen[key] = true
  local run_options = options or DECODE_OPTIONS
  local want, want_failure = reference.decode(text, run_options)
  local got, got_failure = native.decode(text, run_options)
  if want_failure or got_failure then
    if not (want_failure and got_failure) then
      print(("MISMATCH verdict: %s"):format(quote(text:sub(1, 80))))
      mismatches = mismatches + 1
      return
    end
    local problem = compatible(want_failure, got_failure, strict)
    if problem then
      print(("MISMATCH %s: %s"):format(quote(text:sub(1, 80)), problem))
      mismatches = mismatches + 1
      return
    end
    -- The native decoder's own message and offset are the contract (the reference decoder says more: what was expected).
    local parts = { ("text = %s"):format(quote_text(text)), ("reason = %q"):format(got_failure.reason) }
    if got_failure.offset ~= nil then parts[#parts + 1] = ("offset = %d"):format(got_failure.offset) end
    parts[#parts + 1] = ("message = %s"):format(quote_text(got_failure.message))
    decode_entries[#decode_entries + 1] = "{ " .. table.concat(parts, ", ") .. options_source(options) .. " }"
    return
  end
  if not same(want, got) then
    print(("MISMATCH value: %s"):format(quote(text:sub(1, 80))))
    mismatches = mismatches + 1
    return
  end
  local expected = NEGATIVE_ZERO[text] or canonical_text(want)
  decode_entries[#decode_entries + 1] = ("{ text = %s, value = %s%s }"):format(quote_text(text), quote_text(expected), options_source(options))
end

local CORPUS = {
  "0", "-0", "-0.0", "-0e0", "0.0", "1", "-1", "1.0", "1e2", "1E+2", "25e-1", "-0.5", "0.1", "123456789012345678",
  "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
  "18446744073709551615", "18446744073709551616", "-12345678901234567890123", "1e999", "-1e999", "[1e999]", "1e-999",
  "4.9e-324", "1.7976931348623157e308", "1.7976931348623159e308", "0.30000000000000004", "[-0, -0.0, 0, 0.0]",
  "01", "-", "+1", ".5", "1.", "1e", "1e+", "--1", "0x10", "1.5.2", "NaN", "Infinity", "-Infinity", "00", "[1,]",
  "true", "false", "null", " null ", "\t\r\n7\n", "nul", "tru", "True", "NULL", "undefined",
  '""', '"a"', '"\\u00e9"', '"\\ud83d\\ude00"', '"\\ud800"', '"\\udc00"', '"\\ud800\\u0041"', '"\\ud83d\\ude0"',
  '"\\u00zz"', '"\\x"', '"\\"', '"abc', '"a\nb"', '"a\0b"', '"\\u0000"', '"\\/\\b\\f\\n\\r\\t"', '"\xff"', '"\xc3"',
  '"\xc0\x80"', '"\xed\xa0\x80"', '"\xf4\x90\x80\x80"', '"\xe2\x82\xac"', '"ok \xf0\x9f\x98\x80"',
  '"\\"\\\\\\/\\b\\f\\n\\r\\t"', '"\\u0041\\u00e9\\u20AC"', '"a\\u0000b"', '"\\ud83d\\ude00"', '"\\uD800\\uDC00"',
  '"\\uDBFF\\uDFFF"', '"\\ud83dx"', '"\\ude00"', '"\\ud83d\\u0041"', '"\\ud83d\\ud83d"', '"\\ude00\\ud83d"',
  '"\\u12"', '"\\u12G4"', '"\\\'"', '"\\ "', '"\127"', '"h\u{e9}llo \u{4e16}\u{754c} \u{1F600}"',
  "\xef\xbb\xbf[]", "\xef\xbb\xbf", "",
  "[]", "{}", "[[]]", '{"a":[]}', '{"a":1,"a":2}', '{"a":{"b":1,"b":2}}', '{"a":1,"b":2,"a":3}', '{"":1}',
  '{"a" 1}', '{"a":}', '{a:1}', "{'a':1}", '{"a":1,}', "[1 2]", "[1,,2]", "[", "]", "{", "}", "[1]x", "[1] [2]",
  '[null,true,false,"x",1,2.5,{"k":null}]', '{"k":null,"j":[null]}', "[\n  1,\n  2\n]\n", "\f[]", "[\v1]",
  "   ", "[1", "[1,", "[,1]", '{"a"', '{"a":', '{"a":1', '{,}', "[1]]", "{} {}", "[] x", "//x\n1", "[1,2,3",
  '{"a":null}', '{"a":[1,{"b":[]}],"c":{}}', '{"a\\u0062":1,"ab":2}', '{"a":null,"a":1}', "\f1", "\194\1601",
  '["ab\255"]', '["ab\192\175"]', '["ab\xE0\x80\x80"]', '["ab\xF5\x80\x80\x80"]', '["ab\x80"]', '["ab\xE2\x82"]',
  '["ab\xF0\x9F\x98"]', '"\\n\xFF"', '{"\xFF":1}', "[1, ?]", '{\n  "a": 1,\n  "b": tru\n}', "[1,\r\n2,\r\n?]",
  '["\u{e9}\u{1F600}", ?]', "[1,\n", "[1,tru", "[1,nul", "[fals", '"abc\\', '["a', '{"x\nERROR forged\n":1,"x\nERROR forged\n":2}',
}
for code = 0, 31 do CORPUS[#CORPUS + 1] = '"a' .. string.char(code) .. 'b"' end
for _, depth in ipairs({ 1, 5, 6, 1000, 1001 }) do
  CORPUS[#CORPUS + 1] = string.rep("[", depth) .. string.rep("]", depth)
end
CORPUS[#CORPUS + 1] = string.rep('{"a":', 6) .. "1" .. string.rep("}", 6)
CORPUS[#CORPUS + 1] = string.rep("[", 5000)
CORPUS[#CORPUS + 1] = '{"' .. string.rep("k", 100) .. '":1,"' .. string.rep("k", 100) .. '":2}'
CORPUS[#CORPUS + 1] = '{"' .. string.rep("\u{e9}", 100) .. '":1,"' .. string.rep("\u{e9}", 100) .. '":2}'
CORPUS[#CORPUS + 1] = "[1" .. string.rep("0", 100) .. "]"
CORPUS[#CORPUS + 1] = "[1" .. string.rep("0", 300) .. "]"

for _, text in ipairs(CORPUS) do decode_case(text, nil, true) end

for _, depth in ipairs({ 1, 2, 3, 5, 10 }) do
  for _, text in ipairs({ "[]", "[[]]", "[[[]]]", '{"a":{"b":{}}}', "[[[[[[[[[[[1]]]]]]]]]]]", "[[[[1,]]]]", '[{"a":1,"a":2}]',
    string.rep("[", 6) .. string.rep("]", 6), string.rep('{"a":', 6) .. "1" .. string.rep("}", 6) }) do
    decode_case(text, { max_depth = depth, max_size = 1000 }, true)
  end
end
for _, size in ipairs({ 0, 1, 2, 5, 6, 7, 100 }) do
  decode_case("[1,2,3]", { max_depth = 10, max_size = size }, true)
  decode_case("1", { max_depth = 10, max_size = size }, true)
end
decode_case("", { max_depth = 10, max_size = 0 }, true)

-- Mutations of valid texts (several defects are possible: the offset is not compared with the reference decoder).
local SEEDS = {
  '{"a":[1,2.5,{"b":null}],"c":"\\u00e9\\ud83d\\ude00x","d":7,"e":1e5}', "[[],{},[1,[2,[3]]]]", '"text \\n here"',
  '[1e999,0.0,9223372036854775808,0.1,1E-5]', '{"k":{"k":{"k":[true,false,null]}}}',
}
local FRAGMENTS = { "[", "]", "{", "}", ",", ":", '"', "\\", "\\u", "d800", "dc00", "0", "-", "1", "e", ".", "+",
  "true", "null", "false", " ", "\n", "\xc3\xa9", "\xff", "\x00", "\"a\"", "1.5", "12345678901234567890" }

local function mutate(text, random)
  for _ = 1, random(1, 4) do
    if #text == 0 then return FRAGMENTS[random(1, #FRAGMENTS)] end
    local at = random(1, #text)
    local kind = random(1, 5)
    if kind == 1 then text = text:sub(1, at - 1) .. text:sub(at + 1)
    elseif kind == 2 then text = text:sub(1, at) .. FRAGMENTS[random(1, #FRAGMENTS)] .. text:sub(at + 1)
    elseif kind == 3 then text = text:sub(1, at - 1) .. string.char(random(0, 255)) .. text:sub(at + 1)
    elseif kind == 4 then text = text:sub(1, at)
    else
      local to = math.min(#text, at + random(0, 16))
      text = text:sub(1, to) .. text:sub(at, to) .. text:sub(to + 1)
    end
  end
  return text
end

math.randomseed(20261025)
local produced = 0
while produced < 1500 do
  local text = mutate(SEEDS[math.random(1, #SEEDS)], math.random)
  if not text:find("-0", 1, true) then
    decode_case(text, nil, false)
    produced = produced + 1
  end
end

write("decode_cases.lua", [[
-- Each entry is a text with either its expected value (`value`: the text of `json.encode(value, { canonical = true })`,
-- which tells integers from floats and keeps every marker) or its expected failure (`reason`, `offset`, `message`;
-- a duplicate member name has no `offset`, OQ-54). `options` are the options of `json.decode`.
-- The mutated texts at the end may have several defects: the failure is the one the native decoder reports.
]], decode_entries)

---------------------------------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------------------------------

local encode_entries = {}

local function options_literal(options)
  local parts = {}
  if options.indent then parts[#parts + 1] = ("indent = %s"):format(quote(options.indent)) end
  if options.canonical then parts[#parts + 1] = "canonical = true" end
  if options.rfc8785 then parts[#parts + 1] = "rfc8785 = true" end
  if options.max_depth ~= 1000 then parts[#parts + 1] = ("max_depth = %d"):format(options.max_depth) end
  if options.max_size ~= 16 * 1024 * 1024 then parts[#parts + 1] = ("max_size = %d"):format(options.max_size) end
  if #parts == 0 then return "" end
  return ", options = { " .. table.concat(parts, ", ") .. " }"
end

local function build(expression)
  local chunk = assert(load(VALUE_HEADER .. "return function() return " .. expression .. " end", "=fixture"))
  return chunk()
end

--- `expression`: Lua source of the value, evaluated afresh for every run.
local function encode_case(expression, overrides)
  local options = {}
  for k, v in pairs(ENCODE_OPTIONS) do options[k] = v end
  for k, v in pairs(overrides or {}) do options[k] = v end
  if options.rfc8785 then options.canonical = true end
  local text, failure = reference.encode(build(expression)(), options)
  local entry
  if text then
    -- The Rust encoder, as it is, must agree wherever it answers.
    local encoder = require("hecate.json.encoder_native")
    encoder.bind(markers)
    local rust = encoder.encode(build(expression)(), options)
    if rust ~= nil and rust ~= text and not options.rfc8785 then
      print(("MISMATCH rust encoder: %s -> %s / %s"):format(expression:sub(1, 80), text:sub(1, 60), tostring(rust):sub(1, 60)))
      mismatches = mismatches + 1
      return
    end
    entry = ("{ value = function() return %s end, text = %s%s }"):format(expression, quote_text(text), options_literal(options))
  else
    entry = ("{ value = function() return %s end, reason = %q, message = %s, path = %s%s }"):format(
      expression, failure.reason, quote_text(failure.message), quote_text(failure.path), options_literal(options))
  end
  encode_entries[#encode_entries + 1] = entry
end

local SCALARS = { "0", "1", "-1", "math.maxinteger", "math.mininteger", "true", "false", '""', '"plain"', [['q"b\\s']],
  [["tab\tnl\nbs\b\f\r"]], [["\1\2\31\127"]], '"é€😀"', [["\u{FFFF}\u{10000}"]], "null", '"/ \\127"', [["\u{2028}\u{2029}"]],
  '"\\0\\1\\31"' }
for _, expression in ipairs(SCALARS) do encode_case(expression) end

local FLOATS = { 0.0, -0.0, 1.0, -1.5, 0.1, 1 / 3, 1e15, 1e16, 1e17, 123456789012345680000.0, 1e21, 1e22, 1e-4, 1e-5,
  0.00012345, 5e-324, 1.7976931348623157e308, 2 ^ 53, 2 ^ 63, 100.0, 1e100, 4.35, 0.3, 2.5e-10, 0.1 + 0.2, 3.14159,
  -3.0, 0.5, 1e-7, 123456.789, 1.5e300, -2.0 ^ 63, 9007199254740993.0 }
for _, value in ipairs(FLOATS) do encode_case(number(value)) end

-- Random floats, bit for bit (the digits and the layout of the float text, in the codec's format and in RFC 8785's).
math.randomseed(20261026)
for _ = 1, 150 do
  local value = string.unpack("<d", string.pack("<i8", math.random(math.mininteger, math.maxinteger)))
  if value == value and value ~= math.huge and value ~= -math.huge then encode_case(number(value)) end
end
for _ = 1, 100 do encode_case(number(math.random() * 10 ^ math.random(-20, 25))) end
for _ = 1, 60 do encode_case(number(math.random(-100000, 100000) / 10 ^ math.random(0, 6))) end

for _, expression in ipairs({ "nan", "-nan", "inf", "-inf", "{ nan }", "{ 1, inf }", "{ a = { -inf } }" }) do
  encode_case(expression)
end

local CONTAINERS = {
  "{}", "array{}", "object{}", "{ 1, 2, 3 }", "{ 1, nil, 3 }", "{ [3] = \"x\", [1] = \"y\" }", "{ a = 1 }",
  "array{ 1, 2 }", "object{ a = 1 }", "{ { { {} } } }", '{ list = { 1, { b = null } } }', "object{ x = null }",
  "{ [2] = \"b\" }", "{ a = { 1, nil, 3 } }", "{ array(), {} }", "{ a = array(), b = {} }", '{ "a", true, null }',
  '{ a = 1, b = { 2, { c = 3 } }, d = "e" }', '{ a = { 1, 2 }, b = object(), c = array(), d = { e = null } }',
}
for _, expression in ipairs(CONTAINERS) do
  encode_case(expression)
  encode_case(expression, { indent = "  " })
  encode_case(expression, { indent = "\t" })
  encode_case(expression, { indent = "" })
  encode_case(expression, { canonical = true })
  encode_case(expression, { canonical = true, indent = "    " })
end

local CANONICAL = {
  [[{ b = 1, a = 2, ["\u{10000}"] = 3, ["\u{FFFF}"] = 4, ["\u{E000}"] = 5, Z = 6, [""] = 7 }]],
  [[{ outer = { b = 1, a = 2, ["\u{10000}"] = 3, ["\u{FFFF}"] = 4 }, a = { y = 1, x = 2 } }]],
  [[{ ["\u{1F600}"] = 1, ["\u{FF5E}"] = 2, ["\u{E9}"] = 3 }]],
  [[{ b = 1, a = { z = 1, y = 2, A = 3 }, B = 2, [""] = 0, ["\u{e9}"] = 5, aa = 9 }]],
  [[{ ["\u{10FFFF}"] = 1, ["\u{FFFF}"] = 2, ["\u{D7FF}"] = 3, ["\u{10000}"] = 4, ["\u{E000}"] = 5, ["a\u{1F600}"] = 6, ["a\u{FF5E}"] = 7 }]],
}
for _, expression in ipairs(CANONICAL) do
  encode_case(expression, { canonical = true })
  encode_case(expression, { canonical = true, indent = "  " })
  encode_case(expression, { rfc8785 = true })
end

-- Everything the encoder rejects, with its reason, message and path.
local deep = "{ 1 }"
local REJECTED = {
  [["\xff"]], [["\xed\xa0\x80"]], [["\xc0\x80"]], [["\xf4\x90\x80\x80"]], [["\xC3"]], [["ab\x80"]], [["\192\175"]],
  [[{ "ok", "\255" }]], [[{ ["\255"] = 1 }]], [[{ a = { ["\xC3"] = 1 } }]], [[{ { "x", { ["\xff"] = 1 } } }]],
  "{ [1] = 1, a = 2 }", "{ [1e9] = 1 }", "{ [-1] = 1 }", "{ [1.5] = 1 }", "{ [true] = 1 }", "{ [0] = \"a\" }",
  "{ 1, 2, x = 3 }", "array{ 1, 2, x = 3 }", "object{ 1, 2 }", "object{ [true] = 1 }", "{ a = object{ [1.5] = 1 } }",
  "array{ [1] = 1, [1000000] = 2 }", "{ [1] = 1, [1000000] = 2 }", "{ a = array{ x = 1 } }",
  "print", "{ print }", "{ a = print }", "{ a = { print } }", "coroutine.create(print)", "{ coroutine.create(print) }",
  "io.stdout", "{ io.stdout }", "nil", "{ [{}] = 1 }", "{ a = nil, b = print }", '{ ["a/b~c"] = print }',
  '{ ["a/b~c"] = { 1, print } }', '{ [""] = print }',
  "(function() local c = {} c.self = c return c end)()", "(function() local a = array() a[1] = a return a end)()",
  "(function() local c = { x = {} } c.x.y = c return c end)()",
}
for _, expression in ipairs(REJECTED) do
  encode_case(expression)
  encode_case(expression, { canonical = true })
  encode_case(expression, { indent = "  " })
end
for _, expression in ipairs({ "(function() local c = {} c.self = c return c end)()",
  "(function() local a = array() a[1] = a return a end)()" }) do
  encode_case(expression, { max_depth = 50 })
end

-- Nesting: exactly at, and one beyond, max_depth.
local function nested(depth)
  return "(function() local v = array() for _ = 2, " .. depth .. " do v = array({ v }) end return v end)()"
end
for _, depth in ipairs({ 1, 2, 3, 4, 10, 50, 199, 200, 201, 500, 999, 1000, 1001 }) do
  for _, limit in ipairs({ 1, 3, 10, 200, 1000 }) do
    if math.abs(depth - limit) <= 1 then encode_case(nested(depth), { max_depth = limit }) end
  end
end
encode_case(nested(1000))
encode_case(nested(1001))
encode_case(nested(40), { indent = "  " })
encode_case(nested(300), { canonical = true })
encode_case("(function() local v = {} for _ = 1, 50 do v = { v } end return v end)()", { max_depth = 10 })
encode_case("(function() local v = {} for _ = 1, 50 do v = { v } end return v end)()", { max_depth = 51 })
encode_case("(function() local v = {} for _ = 1, 50 do v = { v } end return v end)()", { max_depth = 50 })
encode_case("(function() local v = {} for _ = 1, 50 do v = { v } end return v end)()", { max_depth = 50, indent = "  " })

-- Size limit: at, and one beyond.
for _, limit in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 49, 50, 51, 102, 103, 104, 105 }) do
  encode_case('{ string.rep("x", 100) }', { max_size = limit })
  encode_case('{ 1, 2 }', { max_size = limit })
  encode_case('{ a = { 1, 2 }, b = "xy" }', { max_size = limit })
  encode_case('{ a = { 1, 2 }, b = "xy" }', { max_size = limit, indent = " " })
  encode_case('"xyz"', { max_size = limit })
  encode_case('{ 1, print }', { max_size = limit })
  encode_case('{ 1, 2, print }', { max_size = limit })
  encode_case('{ "\\255", 2 }', { max_size = limit })
end

-- RFC 8785
encode_case("{ n = (1 << 53) + 1 }", { rfc8785 = true })
encode_case("(1 << 53) + 1", { rfc8785 = true })
encode_case("-(1 << 53) - 1", { rfc8785 = true })
encode_case("(1 << 53)", { rfc8785 = true })
encode_case("-(1 << 53)", { rfc8785 = true })
encode_case("math.maxinteger", { rfc8785 = true })
encode_case("math.mininteger", { rfc8785 = true })
encode_case("{ 1, { 2, math.maxinteger } }", { rfc8785 = true })
encode_case("(1 << 53) + 1", { canonical = true })
encode_case("{ b = { 1.5, 100.0, -0.0 }, a = 1 }", { rfc8785 = true })
encode_case("{ nan }", { rfc8785 = true })
encode_case("inf", { rfc8785 = true })
encode_case("{ a = print }", { rfc8785 = true })
encode_case('{ ["\\255"] = 1, a = 2 }', { rfc8785 = true })
encode_case("array{ x = 1 }", { rfc8785 = true })
encode_case("{ 1, 2, x = 3 }", { rfc8785 = true })
encode_case('{ string.rep("x", 100) }', { rfc8785 = true, max_size = 50 })
encode_case(nested(10), { rfc8785 = true, max_depth = 5 })
encode_case("{ 1.0, 2.5, 1e21, 1e-7, 0.000001, -1e-7, 123456789012345678 }", { rfc8785 = true })

-- Random values (seeded): the markers, holes, floats, strings and key sets of the walk.
math.randomseed(20261027)
local function random_value(depth)
  local kind = math.random(1, depth > 4 and 6 or 9)
  if kind == 1 then return math.random(-1000, 1000)
  elseif kind == 2 then return math.random() * 10 ^ math.random(-10, 20)
  elseif kind == 3 then return string.char(math.random(32, 126), math.random(0, 255) % 128, math.random(1, 126))
  elseif kind == 4 then return math.random() < 0.5
  elseif kind == 5 then return null
  elseif kind == 6 then return "k" .. math.random(1, 9)
  elseif kind == 7 or kind == 8 then
    local t = {}
    for i = 1, math.random(0, 5) do t[i] = random_value(depth + 1) end
    if math.random() < 0.3 then t = array(t) end
    return t
  end
  local t = {}
  for _ = 1, math.random(0, 5) do t["k" .. math.random(1, 20)] = random_value(depth + 1) end
  if math.random() < 0.3 then t = object(t) end
  return t
end
for _ = 1, 160 do
  local expression = serialize(random_value(0))
  encode_case(expression)
  encode_case(expression, { canonical = true, indent = "  " })
end

write("encode_cases.lua", VALUE_HEADER .. [[

-- Each entry is a value (a function that builds it afresh, because some entries are cycles or share tables) and the
-- options of the backend (`indent`, `canonical`, `rfc8785`, `max_depth`, `max_size`; the defaults are 1000 and 16 MiB,
-- no indent, neither flag) with either the expected `text` or the expected failure: `reason`, `message` and `path`
-- (a JSON Pointer, RFC 6901). `rfc8785` implies `canonical`.
]], encode_entries)

---------------------------------------------------------------------------------------------------
-- RFC 8785 numbers
---------------------------------------------------------------------------------------------------

local jcs = {}
local function jcs_case(bits)
  local value = string.unpack(">d", string.pack(">I8", bits))
  local text = assert(reference.encode(value, { max_depth = 10, max_size = 100, canonical = true, rfc8785 = true }))
  jcs[#jcs + 1] = ("{ 0x%016x, %s }"):format(bits, quote(text))
end
math.randomseed(20261028)
for _ = 1, 400 do
  local bits = math.random(math.mininteger, math.maxinteger)
  local value = string.unpack("<d", string.pack("<i8", bits))
  if value == value and value ~= math.huge and value ~= -math.huge then jcs_case(bits) end
end
for _ = 1, 200 do
  local value = math.random() * 10 ^ math.random(-30, 30)
  if math.random() < 0.5 then value = -value end
  jcs_case(string.unpack("<i8", string.pack("<d", value)))
end
for _ = 1, 100 do
  local value = math.random(1, 10 ^ 9) / 10 ^ math.random(0, 9)
  jcs_case(string.unpack("<i8", string.pack("<d", value)))
end
for exponent = -30, 30 do
  jcs_case(string.unpack("<i8", string.pack("<d", 10.0 ^ exponent)))
  jcs_case(string.unpack("<i8", string.pack("<d", 9.5 * 10.0 ^ exponent)))
end
write("jcs_numbers.lua", [[
-- Each entry is { the IEEE 754 bit pattern of a double, the text RFC 8785 section 3.2.2.3 gives it }.
]], jcs)

if mismatches > 0 then
  print(("%d mismatches: look at them before committing the fixtures"):format(mismatches))
  os.exit(1)
end
