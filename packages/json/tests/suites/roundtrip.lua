-- Property-style tests (package invariants): decode(encode(x)) == x for every value the codec can
-- encode, integer/float fidelity, and text stability. A fixed seed makes failures reproducible.
-- Shared suite: loaded once per backend by tests/unit/roundtrip_<backend>_test.lua with the backend name as
-- argument (`...`), so that the reference and native backends meet exactly the same assertions.
local test = require("harness.test")
local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")
local backend_name = ...
local T = test.Case("JsonRoundTripTest[" .. backend_name .. "]")

function T:set_up() backend.use(backend_name) end

function T:tear_down() backend.use(nil) end

local SEED = 20261019
local CASES = 400

---------------------------------------------------------------------------------------------------
-- Generators
---------------------------------------------------------------------------------------------------

local function random_integer(random)
  local pick = random(1, 6)
  if pick == 1 then return math.maxinteger end
  if pick == 2 then return math.mininteger end
  if pick == 3 then return random(-10, 10) end
  if pick == 4 then return (1 << random(50, 62)) + random(-3, 3) end
  if pick == 5 then return -(1 << random(50, 62)) + random(-3, 3) end
  return random(math.mininteger, math.maxinteger)
end

local function random_float(random)
  local pick = random(1, 8)
  if pick == 1 then return random(-5, 5) + 0.0 end -- integer-valued floats
  if pick == 2 then return 2.0 ^ random(50, 70) end
  if pick == 3 then return -0.0 end
  if pick == 4 then return random() end
  if pick == 5 then return (random() - 0.5) * 10.0 ^ random(-300, 300) end
  if pick == 6 then return 5e-324 * random(1, 1000) end
  if pick == 7 then return 1.7976931348623157e308 * (random(0, 1) == 0 and 1 or -1) end
  local value
  repeat -- any finite bit pattern
    value = string.unpack("<d", string.pack("<I8", random(math.mininteger, math.maxinteger)))
  until value == value and value ~= math.huge and value ~= -math.huge
  return value
end

local ALPHABET = { "a", "Z", "0", " ", '"', "\\", "/", "\n", "\t", "\0", "\31", "\127", "~", "\u{e9}", "\u{20ac}",
  "\u{2028}", "\u{ffff}", "\u{10000}", "\u{1F600}", "\u{10ffff}", "\u{d7ff}", "\u{e000}" }

local function random_string(random)
  local parts = {}
  for i = 1, random(0, 12) do parts[i] = ALPHABET[random(1, #ALPHABET)] end
  return table.concat(parts)
end

local function random_value(random, depth)
  local pick = random(1, depth >= 4 and 6 or 9)
  if pick == 1 then return json.null end
  if pick == 2 then return random(0, 1) == 1 end
  if pick == 3 then return random_integer(random) end
  if pick == 4 then return random_float(random) end
  if pick <= 6 then return random_string(random) end
  if pick <= 8 then
    local array = json.array()
    for i = 1, random(0, 5) do array[i] = random_value(random, depth + 1) end
    return array
  end
  local object = json.object()
  for _ = 1, random(0, 5) do object[random_string(random)] = random_value(random, depth + 1) end
  return object
end

---------------------------------------------------------------------------------------------------
-- Strict equality: same shape, same markers, same number subtype, same bits for floats
---------------------------------------------------------------------------------------------------

local function same(a, b, path)
  local kind = type(a)
  if kind ~= type(b) then return false, path .. ": type " .. kind .. " vs " .. type(b) end
  if kind == "number" then
    if math.type(a) ~= math.type(b) then return false, ("%s: %s vs %s"):format(path, math.type(a), math.type(b)) end
    if math.type(a) == "float" then
      if string.pack("<d", a) ~= string.pack("<d", b) then return false, ("%s: %.17g vs %.17g"):format(path, a, b) end
    elseif a ~= b then
      return false, ("%s: %d vs %d"):format(path, a, b)
    end
    return true
  end
  if kind ~= "table" then
    if a ~= b then return false, ("%s: %s vs %s"):format(path, tostring(a), tostring(b)) end
    return true
  end
  if a == json.null or b == json.null then
    return a == b, path .. ": null mismatch"
  end
  if json.is_array(a) ~= json.is_array(b) or json.is_object(a) ~= json.is_object(b) then
    return false, path .. ": marker mismatch"
  end
  for key, value in pairs(a) do
    local ok, why = same(value, b[key], path .. "/" .. tostring(key))
    if not ok then return false, why end
  end
  for key in pairs(b) do
    if a[key] == nil then return false, path .. "/" .. tostring(key) .. ": extra member" end
  end
  return true
end

local function check(self, value, label)
  local text = json.encode(value)
  local decoded = json.decode(text)
  local ok, why = same(value, decoded, "")
  self:assert_true(ok, ("%s: %s in %s"):format(label, tostring(why), text))
  self:assert_equal(json.encode(decoded, { canonical = true }), json.encode(value, { canonical = true }), label .. " (canonical text)")
  return text
end

---------------------------------------------------------------------------------------------------

function T:test_decode_of_encode_is_the_identity_for_random_values()
  local random = math.random
  math.randomseed(SEED)
  for case = 1, CASES do
    check(self, random_value(random, 0), "case " .. case)
  end
end

function T:test_encode_is_a_fixed_point_after_one_round()
  math.randomseed(SEED + 1)
  for case = 1, CASES do
    local text = json.encode(random_value(math.random, 0), { canonical = true })
    self:assert_equal(text, json.encode(json.decode(text), { canonical = true }), "case " .. case)
  end
end

function T:test_pretty_and_compact_texts_decode_to_the_same_value()
  math.randomseed(SEED + 2)
  for case = 1, 100 do
    local value = random_value(math.random, 0)
    local ok, why = same(json.decode(json.encode(value)), json.decode(json.encode(value, { indent = 3 })), "")
    self:assert_true(ok, "case " .. case .. ": " .. tostring(why))
  end
end

function T:test_every_integer_and_float_keeps_its_subtype()
  math.randomseed(SEED + 3)
  for case = 1, CASES do
    local integer, float = random_integer(math.random), random_float(math.random)
    local decoded = json.decode(json.encode({ i = integer, f = float }))
    self:assert_equal("integer", math.type(decoded.i), "case " .. case)
    self:assert_equal(integer, decoded.i)
    self:assert_equal("float", math.type(decoded.f), "case " .. case)
    self:assert_equal(string.pack("<d", float), string.pack("<d", decoded.f), ("case %d: %.17g"):format(case, float))
  end
end

function T:test_integer_valued_floats_do_not_collapse_into_integers()
  for _, value in ipairs({ 0.0, -0.0, 1.0, -1.0, 100.0, 2.0 ^ 53, 2.0 ^ 63, 1e21, -1e300 }) do
    self:assert_equal("float", math.type(json.decode(json.encode(value))), tostring(value))
    self:assert_equal("float", math.type(json.decode(json.encode({ value }))[1]), tostring(value))
  end
  self:assert_equal("integer", math.type(json.decode(json.encode(1))))
end

function T:test_the_empty_array_and_the_empty_object_survive_every_container()
  local value = json.object({ a = json.array(), b = json.object(), c = json.array({ json.array(), json.object() }) })
  local ok, why = same(value, json.decode(json.encode(value)), "")
  self:assert_true(ok, tostring(why))
end

function T:test_unicode_strings_round_trip_exactly()
  for _, s in ipairs(ALPHABET) do
    self:assert_equal(s, json.decode(json.encode(s)), ("%q"):format(s))
    self:assert_equal(s, json.decode(json.encode({ [s] = s })) [s])
  end
end

function T:test_every_byte_sequence_either_round_trips_or_is_rejected_on_both_sides()
  math.randomseed(SEED + 4)
  for case = 1, CASES do
    local bytes = {}
    for i = 1, math.random(0, 8) do bytes[i] = string.char(math.random(0, 255)) end
    local s = table.concat(bytes)
    local ok, text = pcall(json.encode, s)
    if ok then
      self:assert_true(utf8.len(s) ~= nil, "accepted invalid UTF-8, case " .. case)
      self:assert_equal(s, json.decode(text))
    else
      self:assert_true(utf8.len(s) == nil, ("rejected valid UTF-8 %q, case %d"):format(s, case))
    end
  end
end

function T:test_decoding_never_raises_anything_but_a_decode_error()
  math.randomseed(SEED + 5)
  local pieces = { "[", "]", "{", "}", ",", ":", '"', "\\", "u", "d800", "1", "-", ".", "e", "E", "+", "0", "true", "nul", " ", "\n", "\255", "\0", "a" }
  for case = 1, 2000 do
    local parts = {}
    for i = 1, math.random(1, 12) do parts[i] = pieces[math.random(1, #pieces)] end
    local text = table.concat(parts)
    local ok, err = pcall(json.decode, text)
    if not ok then
      self:assert_equal("hecate.json.DecodeError", type(err) == "table" and err.code, ("%q -> %s"):format(text, tostring(err)))
    end
  end
end

function T:test_a_decoded_value_always_encodes_back()
  math.randomseed(SEED + 6)
  local pieces = { "[", "]", "{", "}", ",", ":", '"a"', "1", "1.5", "null", "true", " " }
  for case = 1, 2000 do
    local parts = {}
    for i = 1, math.random(1, 10) do parts[i] = pieces[math.random(1, #pieces)] end
    local text = table.concat(parts)
    local ok, value = pcall(json.decode, text)
    if ok then
      local again = json.decode(json.encode(value))
      local equal, why = same(value, again, "")
      self:assert_true(equal, ("%q: %s"):format(text, tostring(why)))
    end
  end
end

return T
