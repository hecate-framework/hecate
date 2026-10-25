-- The native decoder (csrc/native.c) against the expected-output fixtures (tests/fixtures/decode_cases.lua, generated from
-- the pure-Lua reference backend before it was removed, OQ-53): the same value for every valid text, and the same
-- reason, offset and message for every rejected one. The native module is required at run time: a module that is not
-- built fails the file with the build command.
local test = require("harness.test")
local json = require("hecate.json")
local T = test.Case("JsonDecodeFixturesTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local built, native = pcall(require, "hecate.json.native")

local DEFAULTS = { max_depth = 1000, max_size = 16 * 1024 * 1024 }

function T:set_up()
  if not built then self:fail("hecate.json.native is not built: run `lua tools/run.lua build-native json`\n" .. tostring(native)) end
end

function T:test_every_fixture_gives_its_value_or_its_failure()
  local cases = dofile(here .. "/../fixtures/decode_cases.lua")
  self:assert_true(#cases > 1500)
  for index, case in ipairs(cases) do
    local options = case.options or DEFAULTS
    local value, failure = native.decode(case.text, options)
    local label = ("case %d (%q)"):format(index, case.text:sub(1, 60))
    if case.value then
      self:assert_nil(failure, label .. ": " .. tostring(failure and failure.message))
      self:assert_equal(case.value, json.encode(value, { canonical = true }), label)
    else
      self:assert_nil(value, label .. ": expected the failure " .. case.reason)
      self:assert_not_nil(failure, label)
      self:assert_equal(case.reason, failure.reason, label)
      self:assert_equal(case.offset, failure.offset, label)
      self:assert_equal(case.message, failure.message, label)
    end
  end
end

-- Lua's own `tonumber` reads a float as C's strtod does: the oracle for the numbers that yyjson reads.
function T:test_random_numbers_decode_to_the_floats_and_integers_of_lua()
  local random = math.random
  math.randomseed(20261019)
  for _ = 1, 5000 do
    local kind = random(1, 4)
    local literal
    if kind == 1 then literal = ("%.17g"):format((random() - 0.5) * 10.0 ^ random(-320, 308))
    elseif kind == 2 then literal = ("%d"):format(random(math.mininteger, math.maxinteger))
    elseif kind == 3 then literal = ("%d.%de%d"):format(random(1, 99999), random(0, 99999999), random(-330, 320))
    else literal = tostring(random(1, 9)) .. ("%d"):format(random(0, math.maxinteger)) .. ("%d"):format(random(0, math.maxinteger)) end
    local want = tonumber(literal)
    if want ~= math.huge and want ~= -math.huge then
      local value, failure = native.decode("[" .. literal .. "]", DEFAULTS)
      self:assert_nil(failure, literal)
      self:assert_equal(math.type(want), math.type(value[1]), literal)
      self:assert_equal(want, value[1], literal)
    end
  end
end

-- The binding does not handle `-0` (OQ-53): the result is whatever yyjson reads. Today it reads the integer literal `-0` as
-- the integer 0 and the float literals as floats that keep their sign; a yyjson update that changes it fails here.
function T:test_negative_zero_is_what_yyjson_reads()
  self:assert_equal("integer", math.type(native.decode("-0", DEFAULTS)))
  self:assert_equal("integer", math.type(native.decode("[-0]", DEFAULTS)[1]))
  for _, text in ipairs({ "-0.0", "-0e0", "-0E+3" }) do
    local value = native.decode(text, DEFAULTS)
    self:assert_equal("float", math.type(value), text)
    self:assert_equal("-0.0", tostring(value), text)
  end
  self:assert_equal("integer", math.type(native.decode("[-1]", DEFAULTS)[1]))
end

function T:test_a_native_caller_that_asks_for_more_than_the_ceiling_gets_the_ceiling()
  local text = ("["):rep(1001) .. ("]"):rep(1001)
  local value, failure = native.decode(text, { max_depth = 5000, max_size = #text })
  self:assert_nil(value)
  self:assert_equal("depth_limit", failure.reason)
  self:assert_equal(1000, failure.offset)
  self:assert_equal("nesting deeper than max_depth (1000)", failure.message)
  self:assert_not_nil(native.decode(("["):rep(1000) .. ("]"):rep(1000), { max_depth = 5000, max_size = #text }))
end

return T
