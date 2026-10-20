-- The Rust encoder (native/src/lib.rs) against the reference encoder: the same text for everything it
-- encodes, and `nil` (decline) for everything the reference encoder rejects or that is RFC 8785.
-- Where the module is not built the file skips, except in CI on POSIX (see tests/suites/load.lua).
local test = require("harness.test")
local markers = require("hecate.json.internal.markers")
local reference = require("hecate.json.internal.reference")
local T = test.Case("JsonEncoderNativeTest")

local built, encoder = pcall(require, "hecate.json.encoder_native")

local OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = false, rfc8785 = false }

local function with(overrides)
  local options = {}
  for k, v in pairs(OPTIONS) do options[k] = v end
  for k, v in pairs(overrides or {}) do options[k] = v end
  return options
end

function T:set_up()
  if not built then
    if (os.getenv("CI") and package.config:sub(1, 1) == "/") then
      self:fail("hecate.json.encoder_native is not built (lua tools/run.lua build-native json)")
    end
    io.stderr:write("# skipped: hecate.json.encoder_native is not built\n")
    self.skipped = true
    return
  end
  encoder.bind(markers)
end

local function agree(self, value, options)
  options = options or OPTIONS
  local want = reference.encode(value, options)
  local got = encoder.encode(value, options)
  if want == nil then
    self:assert_nil(got, "the reference encoder rejects this value: the Rust encoder must decline")
  else
    self:assert_equal(want, got)
  end
end

function T:test_scalars_and_strings_agree()
  if self.skipped then return end
  for _, value in ipairs({ 0, 1, -1, math.maxinteger, math.mininteger, true, false, "", "plain", 'q"b\\s', "tab\tnl\nbs\b\f\r",
    "\1\2\31\127", "é€😀", "\u{FFFF}\u{10000}", markers.null }) do
    agree(self, value)
  end
end

function T:test_floats_agree()
  if self.skipped then return end
  for _, value in ipairs({ 0.0, -0.0, 1.0, -1.5, 0.1, 1 / 3, 1e15, 1e16, 1e17, 123456789012345680000.0, 1e21, 1e22, 1e-4,
    1e-5, 0.00012345, 5e-324, 1.7976931348623157e308, 2 ^ 53, 2 ^ 63, 100.0, 1e100, 4.35, 0.3, 2.5e-10 }) do
    agree(self, value)
  end
end

function T:test_random_floats_agree()
  if self.skipped then return end
  math.randomseed(20261020)
  for _ = 1, 20000 do
    local value = string.unpack("<d", string.pack("<i8", math.random(math.mininteger, math.maxinteger)))
    if value == value and value ~= math.huge and value ~= -math.huge then agree(self, value) end
  end
  for _ = 1, 20000 do agree(self, math.random() * 10 ^ math.random(-20, 25)) end
  for _ = 1, 5000 do agree(self, math.random(-100000, 100000) / 10 ^ math.random(0, 6)) end
end

function T:test_non_finite_numbers_are_declined()
  if self.skipped then return end
  for _, value in ipairs({ 0 / 0, math.huge, -math.huge }) do agree(self, value) end
end

function T:test_containers_agree()
  if self.skipped then return end
  local array, object = markers.array_metatable, markers.object_metatable
  local values = {
    {}, markers.tag({}, array), markers.tag({}, object), { 1, 2, 3 }, { 1, nil, 3 }, { [3] = "x", [1] = "y" },
    { a = 1 }, markers.tag({ 1, 2 }, array), markers.tag({ a = 1 }, object), { { { {} } } },
    { list = { 1, { b = markers.null } } }, markers.tag({ x = markers.null }, object),
  }
  for _, value in ipairs(values) do
    agree(self, value)
    agree(self, value, with({ indent = "  " }))
    agree(self, value, with({ indent = "\t" }))
  end
end

function T:test_canonical_orders_members_by_utf16_code_units()
  if self.skipped then return end
  local value = { b = 1, a = 2, ["\u{10000}"] = 3, ["\u{FFFF}"] = 4, ["\u{E000}"] = 5, Z = 6, [""] = 7 }
  agree(self, value, with({ canonical = true }))
  agree(self, { outer = value, a = { y = 1, x = 2 } }, with({ canonical = true, indent = "  " }))
end

function T:test_what_the_reference_rejects_is_declined()
  if self.skipped then return end
  local cycle = {}
  cycle.self = cycle
  local values = {
    "\xff", "\xed\xa0\x80", "\xc0\x80", { [1] = 1, a = 2 }, { [1e9] = 1 }, { [-1] = 1 }, { [1.5] = 1 }, { [true] = 1 },
    markers.tag({ a = 1 }, markers.array_metatable), markers.tag({ 1 }, markers.object_metatable), print, cycle,
    { a = print }, coroutine.create(print), { [{}] = 1 },
  }
  for _, value in ipairs(values) do agree(self, value) end
end

function T:test_limits_decline()
  if self.skipped then return end
  local deep = {}
  local node = deep
  for _ = 1, 50 do node[1] = {}; node = node[1] end
  agree(self, deep, with({ max_depth = 10 }))
  agree(self, deep, with({ max_depth = 51 }))
  agree(self, deep, with({ max_depth = 50 }))
  agree(self, { string.rep("x", 100) }, with({ max_size = 50 }))
  agree(self, { string.rep("x", 100) }, with({ max_size = 104 }))
  agree(self, { string.rep("x", 100) }, with({ max_size = 103 }))
end

-- The Rust encoder recurses on the native stack: beyond its own depth it declines, and the reference
-- encoder (through the backend) writes the value, up to the max_depth ceiling.
function T:test_a_value_beyond_the_native_depth_is_declined_and_still_encodes_through_the_backend()
  if self.skipped then return end
  local deep = {}
  local node = deep
  for _ = 1, 999 do node[1] = {}; node = node[1] end
  local options = with({ max_depth = 10000 })
  self:assert_nil(encoder.encode(deep, options))
  local text = reference.encode(deep, options)
  self:assert_equal(2000, #text)
  local backend = require("hecate.json.internal.backend")
  backend.use("native")
  local selected = backend.get()
  local got = selected.encode(deep, options)
  backend.use(nil)
  self:assert_true(got == text)
end

function T:test_markers_are_compared_by_identity()
  if self.skipped then return end
  -- A table that merely looks like the null sentinel is an ordinary (empty) object.
  agree(self, setmetatable({}, { __metatable = "hecate.json.null" }))
  agree(self, setmetatable({}, { __name = "hecate.json.array" }))
end

function T:test_random_values_agree()
  if self.skipped then return end
  math.randomseed(20261021)
  local function random_value(depth)
    local kind = math.random(1, depth > 4 and 6 or 9)
    if kind == 1 then return math.random(-1000, 1000)
    elseif kind == 2 then return math.random() * 10 ^ math.random(-10, 20)
    elseif kind == 3 then return string.char(math.random(32, 126), math.random(0, 255) % 128, math.random(1, 126))
    elseif kind == 4 then return math.random() < 0.5
    elseif kind == 5 then return markers.null
    elseif kind == 6 then return "k" .. math.random(1, 9)
    elseif kind == 7 or kind == 8 then
      local t = {}
      for i = 1, math.random(0, 5) do t[i] = random_value(depth + 1) end
      return t
    end
    local t = {}
    for _ = 1, math.random(0, 5) do t["k" .. math.random(1, 20)] = random_value(depth + 1) end
    return t
  end
  for _ = 1, 3000 do
    local value = random_value(0)
    agree(self, value)
    agree(self, value, with({ canonical = true, indent = "  " }))
  end
end

return T
