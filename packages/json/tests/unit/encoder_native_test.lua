-- The Rust encoder (native/src/lib.rs) against the expected-output fixtures (tests/fixtures, generated from the
-- pure-Lua reference backend before it was removed, OQ-53): the same text for every value it encodes, and the same
-- failure (reason, message, JSON Pointer path) for every value it rejects, `canonical` and `rfc8785` included.
-- The native modules are required at run time: a module that is not built fails the file with the build command.
local test = require("harness.test")
local markers = require("hecate.json.internal.markers")
local T = test.Case("JsonEncoderNativeTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local built, encoder = pcall(require, "hecate.json.encoder_native")

local DEFAULTS = { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = false, rfc8785 = false }

local function with(overrides)
  local options = {}
  for k, v in pairs(DEFAULTS) do options[k] = v end
  for k, v in pairs(overrides or {}) do options[k] = v end
  if options.rfc8785 then options.canonical = true end
  return options
end

function T:set_up()
  if not built then self:fail("hecate.json.encoder_native is not built: run `lua tools/run.lua build-native json`\n" .. tostring(encoder)) end
  encoder.bind(markers)
end

function T:test_every_fixture_gives_its_text_or_its_failure()
  local cases = dofile(here .. "/../fixtures/encode_cases.lua")
  self:assert_true(#cases > 1000)
  for index, case in ipairs(cases) do
    local text, failure = encoder.encode(case.value(), with(case.options))
    local label = ("case %d (%s)"):format(index, case.text and "text" or case.reason)
    if case.text then
      self:assert_nil(failure, label .. ": " .. tostring(failure and failure.message))
      self:assert_equal(case.text, text, label)
    else
      self:assert_nil(text, label .. ": expected the failure " .. case.reason)
      self:assert_not_nil(failure, label)
      self:assert_equal(case.reason, failure.reason, label)
      self:assert_equal(case.message, failure.message, label)
      self:assert_equal(case.path, failure.path, label)
    end
  end
end

function T:test_rfc_8785_numbers_follow_the_rfc()
  local numbers = dofile(here .. "/../fixtures/jcs_numbers.lua")
  self:assert_true(#numbers > 500)
  local options = with({ rfc8785 = true })
  for _, vector in ipairs(numbers) do
    local number = string.unpack(">d", string.pack(">I8", vector[1]))
    self:assert_equal(vector[2], encoder.encode(number, options), ("%016x"):format(vector[1]))
  end
end

-- The layout of a float in the codec's own format (README, "Public API"): the fewest of 15, 16 and 17 significant digits
-- that read back as the same float, in the notation of `%g`, with a decimal point or an exponent always present.
local function expected_float(number)
  local text = ("%.15g"):format(number)
  if tonumber(text) ~= number then
    text = ("%.16g"):format(number)
    if tonumber(text) ~= number then text = ("%.17g"):format(number) end
  end
  if not text:find("[.eE]") then text = text .. ".0" end
  return text
end

function T:test_random_floats_are_written_in_the_codec_format()
  math.randomseed(20261029)
  local options = with()
  local function check(value)
    local text, failure = encoder.encode(value, options)
    self:assert_nil(failure)
    self:assert_equal(expected_float(value), text)
    self:assert_equal(value, tonumber(text))
  end
  for _ = 1, 20000 do
    local value = string.unpack("<d", string.pack("<i8", math.random(math.mininteger, math.maxinteger)))
    if value == value and value ~= math.huge and value ~= -math.huge then check(value) end
  end
  for _ = 1, 20000 do check(math.random() * 10 ^ math.random(-20, 25)) end
  for _ = 1, 5000 do check(math.random(-100000, 100000) / 10 ^ math.random(0, 6)) end
end

function T:test_random_floats_read_back_in_the_rfc_8785_format()
  math.randomseed(20261030)
  local options = with({ rfc8785 = true })
  for _ = 1, 20000 do
    local value = string.unpack("<d", string.pack("<i8", math.random(math.mininteger, math.maxinteger)))
    if value == value and value ~= math.huge and value ~= -math.huge then
      local text = encoder.encode(value, options)
      self:assert_equal(value + 0.0, tonumber(text) + 0.0, text) -- reads back as the same double (-0 is "0")
      self:assert_nil(text:find("[^0-9eE%.%+%-]"), text)
    end
  end
end

function T:test_the_result_is_a_text_or_a_failure_never_both()
  local text, failure = encoder.encode({ 1 }, with())
  self:assert_equal("[1]", text)
  self:assert_nil(failure)
  text, failure = encoder.encode(0 / 0, with())
  self:assert_nil(text)
  self:assert_equal("table", type(failure))
  self:assert_equal("non_finite_number", failure.reason)
end

function T:test_markers_are_compared_by_identity()
  -- A table that merely looks like the null sentinel is an ordinary (empty) object.
  self:assert_equal("{}", encoder.encode(setmetatable({}, { __metatable = "hecate.json.null" }), with()))
  self:assert_equal("{}", encoder.encode(setmetatable({}, { __name = "hecate.json.array" }), with()))
  self:assert_equal("null", encoder.encode(markers.null, with()))
end

function T:test_a_value_nested_to_the_ceiling_is_encoded_on_a_small_native_stack()
  local deep = markers.tag({}, markers.array_metatable)
  for _ = 2, 1000 do deep = markers.tag({ deep }, markers.array_metatable) end
  local text = encoder.encode(deep, with())
  self:assert_equal(2000, #text)
  local pretty = encoder.encode(deep, with({ indent = "  ", max_size = 8 * 1024 * 1024 }))
  self:assert_true(#pretty > 2000)
  local canonical = encoder.encode(deep, with({ rfc8785 = true }))
  self:assert_equal(text, canonical)
end

function T:test_arguments_are_checked()
  self:assert_error(function() encoder.encode(1) end)
  self:assert_error(function() encoder.bind({}) end)
  self:assert_error(function() encoder.bind(nil) end)
end

return T
