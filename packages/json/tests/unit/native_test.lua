-- The native backend (yyjson binding, csrc/native.c) against the reference backend: the same value
-- model, the same failures with the same reasons, messages and offsets, on a fixed corpus and on
-- seeded random inputs. The shared suites (tests/suites) already run every public behaviour against
-- both backends; this file pins the equivalence of the two directly, and the binding contract.
-- Where the module is not built the file skips, except in CI (see tests/suites/load.lua).
local test = require("harness.test")
local backend = require("hecate.json.internal.backend")
local reference = require("hecate.json.internal.reference")
local markers = require("hecate.json.internal.markers")
local T = test.Case("JsonNativeTest")

local built, native = pcall(require, "hecate.json.native")

local OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024 }

function T:set_up()
  if not built then
    if (os.getenv("CI")) then self:fail("hecate.json.native is not built (lua tools/run.lua build-native json)") end
    io.stderr:write("# skipped: hecate.json.native is not built\n")
    self.skipped = true
  end
end

-- Structural equality that tells integers from floats, distinguishes -0.0 and compares marker
-- metatables by identity.
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

local function agree(self, text, options)
  options = options or OPTIONS
  local want, want_failure = reference.decode(text, options)
  local got, got_failure = native.decode(text, options)
  local shown = ("%q"):format(text:sub(1, 60))
  if want_failure then
    self:assert_nil(got, shown)
    self:assert_not_nil(got_failure, shown)
    self:assert_equal(want_failure.reason, got_failure.reason, shown)
    self:assert_equal(want_failure.offset, got_failure.offset, shown)
    self:assert_equal(want_failure.message, got_failure.message, shown)
  else
    self:assert_nil(got_failure, shown)
    self:assert_true(same(want, got), "different values for " .. shown)
  end
end

local CORPUS = {
  -- scalars and numbers
  "0", "-0", "-0.0", "-0e0", "0.0", "1", "-1", "1.0", "1e2", "1E+2", "25e-1", "0.1", "123456789012345678",
  "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
  "18446744073709551615", "18446744073709551616", "-12345678901234567890123", "1e999", "-1e999", "1e-999",
  "4.9e-324", "1.7976931348623157e308", "1.7976931348623159e308", "0.30000000000000004", "[-0, -0.0, 0, 0.0]",
  "01", "-", "+1", ".5", "1.", "1e", "1e+", "--1", "0x10", "1.5.2", "NaN", "Infinity", "-Infinity", "00", "[1,]",
  "true", "false", "null", " null ", "\t\r\n7\n", "nul", "tru", "True", "NULL",
  -- strings
  '""', '"a"', '"\\u00e9"', '"\\ud83d\\ude00"', '"\\ud800"', '"\\udc00"', '"\\ud800\\u0041"', '"\\ud83d\\ude0"',
  '"\\u00zz"', '"\\x"', '"\\"', '"abc', '"a\nb"', '"a\0b"', '"\\u0000"', '"\\/\\b\\f\\n\\r\\t"', '"\xff"', '"\xc3"',
  '"\xc0\x80"', '"\xed\xa0\x80"', '"\xf4\x90\x80\x80"', '"\xe2\x82\xac"', '"ok \xf0\x9f\x98\x80"',
  "\xef\xbb\xbf[]", "\xef\xbb\xbf", "",
  -- structure
  "[]", "{}", "[[]]", '{"a":[]}', '{"a":1,"a":2}', '{"a":{"b":1,"b":2}}', '{"a":1,"b":2,"a":3}', '{"":1}',
  '{"a" 1}', '{"a":}', '{a:1}', "{'a':1}", '{"a":1,}', "[1 2]", "[1,,2]", "[", "]", "{", "}", "[1]x", "[1] [2]",
  '[null,true,false,"x",1,2.5,{"k":null}]', '{"k":null,"j":[null]}', "[\n  1,\n  2\n]\n", "\f[]", "[\v1]",
}

function T:test_the_corpus_gives_the_same_values_and_the_same_failures()
  if self.skipped then return end
  for _, text in ipairs(CORPUS) do agree(self, text) end
end

function T:test_limits_give_the_same_failures()
  if self.skipped then return end
  for _, depth in ipairs({ 1, 2, 3, 10 }) do
    for _, text in ipairs({ "[]", "[[]]", "[[[]]]", '{"a":{"b":{}}}', "[[[[[[[[[[[1]]]]]]]]]]]", "[[[[1,]]]]", '[{"a":1,"a":2}]' }) do
      agree(self, text, { max_depth = depth, max_size = 1000 })
    end
  end
  for _, size in ipairs({ 0, 1, 5, 6, 7, 100 }) do agree(self, "[1,2,3]", { max_depth = 10, max_size = size }) end
  agree(self, "", { max_depth = 10, max_size = 0 })
end

function T:test_a_deep_text_is_decoded_up_to_the_depth_ceiling_and_rejected_beyond()
  if self.skipped then return end
  local deep = 10000
  local text = ("["):rep(deep) .. ("]"):rep(deep)
  local options = { max_depth = deep, max_size = #text }
  local value = native.decode(text, options)
  self:assert_true(getmetatable(value) == markers.array_metatable)
  local failure
  value, failure = native.decode(text, { max_depth = deep - 1, max_size = #text })
  self:assert_nil(value)
  self:assert_equal("depth_limit", failure.reason)
  self:assert_equal(deep - 1, failure.offset)
  local beyond = ("["):rep(deep + 2000) .. ("]"):rep(deep + 2000)
  agree(self, beyond, { max_depth = deep + 5000, max_size = #beyond })
  agree(self, ("["):rep(100000), { max_depth = 1000, max_size = 200000 })
end

local function random_text(random)
  local pieces = { "[", "]", "{", "}", ",", ":", '"', "\\", "u", "d800", "dc00", "0", "-", "1", "e", "E", ".", "+",
    "true", "null", "false", " ", "\n", "a", "\xc3\xa9", "\xff", "\x00", "\x7f", "\"a\"", "1.5", "-0", "12345678901234567890" }
  local parts = {}
  for i = 1, random(1, 12) do parts[i] = pieces[random(1, #pieces)] end
  return table.concat(parts)
end

function T:test_random_mutations_of_valid_texts_agree()
  if self.skipped then return end
  local random = math.random
  math.randomseed(20261019)
  local seeds = { '{"a":[1,2.5,{"b":null}],"c":"\\u00e9\\ud83d\\ude00x","d":-0,"e":1e5}', "[[],{},[1,[2,[3]]]]", '"text \\n here"' }
  for _ = 1, 3000 do
    local text = seeds[random(1, #seeds)]
    for _ = 1, random(1, 3) do
      local at = random(1, #text)
      local kind = random(1, 3)
      if kind == 1 then text = text:sub(1, at - 1) .. text:sub(at + 1)
      elseif kind == 2 then text = text:sub(1, at) .. random_text(random) .. text:sub(at + 1)
      else text = text:sub(1, at - 1) .. string.char(random(0, 255)) .. text:sub(at + 1) end
    end
    agree(self, text)
  end
  for _ = 1, 3000 do agree(self, random_text(random)) end
end

function T:test_random_numbers_decode_to_the_same_floats_and_integers()
  if self.skipped then return end
  local random = math.random
  math.randomseed(20261020)
  for _ = 1, 5000 do
    local kind = random(1, 4)
    local literal
    if kind == 1 then literal = ("%.17g"):format((random() - 0.5) * 10.0 ^ random(-320, 308))
    elseif kind == 2 then literal = ("%d"):format(random(math.mininteger, math.maxinteger))
    elseif kind == 3 then literal = ("%d.%de%d"):format(random(0, 99999), random(0, 99999999), random(-330, 320))
    else literal = tostring(random(0, 9)) .. ("%d"):format(random(0, math.maxinteger)) .. ("%d"):format(random(0, math.maxinteger)) end
    agree(self, "[" .. literal .. "]")
  end
end

function T:test_decoded_containers_carry_the_markers_and_null_is_the_lua_value()
  if self.skipped then return end
  local value = native.decode('{"a":[],"b":{},"c":null,"d":[null]}', OPTIONS)
  self:assert_true(getmetatable(value) == markers.object_metatable)
  self:assert_true(getmetatable(value.a) == markers.array_metatable)
  self:assert_true(getmetatable(value.b) == markers.object_metatable)
  self:assert_true(value.c == markers.null)
  self:assert_true(value.d[1] == markers.null)
end

function T:test_bind_keeps_the_markers_it_is_given()
  if self.skipped then return end
  local array_metatable, object_metatable = {}, {}
  local null = setmetatable({}, { __metatable = "other null" })
  native.bind({ null = null, array_metatable = array_metatable, object_metatable = object_metatable })
  local value = native.decode('{"a":[null]}', OPTIONS)
  local ok, err = pcall(function()
    self:assert_true(getmetatable(value) == object_metatable)
    self:assert_true(getmetatable(value.a) == array_metatable)
    self:assert_true(value.a[1] == null)
  end)
  native.bind(markers)
  if not ok then error(err, 0) end
  self:assert_true(getmetatable(native.decode("[]", OPTIONS)) == markers.array_metatable)
  self:assert_error(function() native.bind({}) end)
  self:assert_error(function() native.bind(nil) end)
end

function T:test_binary_safe_strings_and_members()
  if self.skipped then return end
  local value = native.decode('{"a\\u0000b":"x\\u0000y"}', OPTIONS)
  self:assert_equal("x\0y", value["a\0b"])
  self:assert_error(function() native.decode({}, OPTIONS) end)
  self:assert_error(function() native.decode("1") end)
end

function T:test_encode_delegates_to_the_reference_backend()
  if self.skipped then return end
  local value = markers.tag({ 1, 2.5, "x", markers.null }, markers.array_metatable)
  local options = { max_depth = 10, max_size = 1000, canonical = false }
  local text = native.encode(value, options)
  self:assert_equal(reference.encode(value, options), text)
  self:assert_equal("[1,2.5,\"x\",null]", text)
  local none, failure = native.encode(0 / 0, options)
  self:assert_nil(none)
  self:assert_equal("non_finite_number", failure.reason)
  self:assert_equal("", failure.path)
end

function T:test_the_seam_selects_the_native_backend_when_it_is_built()
  if self.skipped then return end
  backend.use(nil)
  local selected, name = backend.get()
  backend.use(nil)
  self:assert_equal("native", name)
  self:assert_true(selected.decode == native.decode)
end

return T
