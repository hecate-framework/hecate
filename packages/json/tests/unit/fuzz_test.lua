-- Fuzzing the codec with properties and no oracle (OQ-53): mutations of valid texts (the built-in seeds and, when
-- downloaded, the JSONTestSuite files) must never crash or raise anything but a `DecodeError`; a text that decodes must
-- encode, the text must be valid UTF-8 and must decode back to the same value; random values, valid or not, must
-- encode to valid UTF-8 or raise an `EncodeError`, and what encodes must decode back to itself.
-- Default: a fixed seed and a fixed number of iterations (a regression test). For a longer search:
--   HECATE_FUZZ_SECONDS=60 HECATE_FUZZ_SEED=1234 lua tools/run.lua test json
-- A failure names the seed and the text, so that it can be replayed and added to the fixtures.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonFuzzTest")

local ITERATIONS = 4000

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."

-- Structural equality that tells integers from floats, distinguishes -0.0 and compares marker metatables by identity.
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

local SEEDS = {
  '{"a":[1,2.5,{"b":null}],"c":"\\u00e9\\ud83d\\ude00x","d":-0,"e":1e5}', "[[],{},[1,[2,[3]]]]", '"text \\n here"',
  '[1e999,-0.0,9223372036854775808,0.1,1E-5]', '{"k":{"k":{"k":[true,false,null]}}}',
}

-- The JSONTestSuite files that are valid or implementation-defined, when the corpus has been downloaded.
local function corpus_seeds()
  local dir = here .. "/../../../../.hecate/fixtures/json/JSONTestSuite/test_parsing/"
  local manifest = io.open(here .. "/../JSONTestSuite.manifest", "r")
  local list = {}
  if not manifest then return list end
  for name in manifest:lines() do
    if name:match("^[yi]_") then
      local file = io.open(dir .. name, "rb")
      if file then
        local text = file:read("a")
        file:close()
        if #text <= 4096 then list[#list + 1] = text end
      end
    end
  end
  manifest:close()
  return list
end

local FRAGMENTS = { "[", "]", "{", "}", ",", ":", '"', "\\", "\\u", "d800", "dc00", "0", "-", "1", "e", ".", "+",
  "true", "null", "false", " ", "\n", "\xc3\xa9", "\xff", "\x00", "\"a\"", "1.5", "-0", "12345678901234567890" }

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

local REASONS = {
  syntax = true, invalid_utf8 = true, invalid_escape = true, lone_surrogate = true, control_character = true,
  byte_order_mark = true, duplicate_key = true, number_out_of_range = true, depth_limit = true, size_limit = true,
}

-- Returns a description of the first property that `text` breaks, or nil.
local function broken(text)
  local ok, value = pcall(json.decode, text)
  if not ok then
    if not core.is_instance_of(value, json.DecodeError) then return "decode raised " .. tostring(value) end
    local context = value.context
    if not REASONS[context.reason] then return "unknown reason " .. tostring(context.reason) end
    if context.offset ~= nil and (context.offset < 0 or context.offset > #text) then
      return "offset " .. tostring(context.offset) .. " outside the text"
    end
    return nil
  end
  local encoded, encoded_value = pcall(json.encode, value)
  if not encoded then return "a decoded value does not encode: " .. tostring(encoded_value) end
  if utf8.len(encoded_value) == nil then return "the encoded text is not valid UTF-8" end
  local again = json.decode(encoded_value)
  if not same(value, again) then return "the encoded text does not decode back to the value" end
  if json.encode(again, { canonical = true }) ~= json.encode(value, { canonical = true }) then return "the canonical text is not stable" end
  return nil
end

function T:test_mutated_texts_never_crash_and_what_decodes_round_trips()
  local seed = tonumber(os.getenv("HECATE_FUZZ_SEED")) or 20261022
  local seconds = tonumber(os.getenv("HECATE_FUZZ_SECONDS"))
  math.randomseed(seed)
  local random = math.random
  local seeds = corpus_seeds()
  for _, text in ipairs(SEEDS) do seeds[#seeds + 1] = text end
  local deadline = seconds and (os.clock() + seconds)
  local count = 0
  while true do
    local text = mutate(seeds[random(1, #seeds)], random)
    local problem = broken(text)
    if problem then
      self:fail(("seed %d, iteration %d: %s for %q"):format(seed, count, problem, text:sub(1, 200)))
    end
    count = count + 1
    if deadline then
      if os.clock() >= deadline then break end
    elseif count >= ITERATIONS then
      break
    end
  end
  io.stderr:write(("# fuzz: %d texts, seed %d\n"):format(count, seed))
end

local function random_value(random, depth)
  local kind = random(1, depth > 4 and 9 or 13)
  if kind == 1 then return random(-1000, 1000)
  elseif kind == 2 then return random() * 10 ^ random(-10, 20)
  elseif kind == 3 then return string.char(random(32, 126), random(0, 255), random(1, 126)) -- may be invalid UTF-8
  elseif kind == 4 then return random() < 0.5
  elseif kind == 5 then return json.null
  elseif kind == 6 then return "k" .. random(1, 9)
  elseif kind == 7 then return ({ 0 / 0, math.huge, -math.huge, print, -0.0, math.mininteger })[random(1, 6)]
  elseif kind == 8 then return random(math.mininteger, math.maxinteger)
  elseif kind == 9 then return "\u{e9}\u{1F600}"
  elseif kind == 10 or kind == 11 then
    local t = {}
    for i = 1, random(0, 5) do t[i] = random_value(random, depth + 1) end
    if random() < 0.3 then t = json.array(t) end
    return t
  end
  local t = {}
  for _ = 1, random(0, 5) do t["k" .. random(1, 20)] = random_value(random, depth + 1) end
  if random() < 0.3 then t = json.object(t) end
  return t
end

function T:test_random_values_encode_to_valid_utf8_or_raise_an_encode_error_and_round_trip()
  math.randomseed(20261023)
  local encoded_count = 0
  for case = 1, 3000 do
    local value = random_value(math.random, 0)
    for _, options in ipairs({ {}, { canonical = true, indent = 2 }, { canonical = "rfc8785" } }) do
      local ok, text = pcall(json.encode, value, options)
      if ok then
        self:assert_true(utf8.len(text) ~= nil, ("case %d: invalid UTF-8 in %q"):format(case, text))
        local decoded = json.decode(text)
        if options.canonical ~= "rfc8785" then
          self:assert_equal(json.encode(decoded, { canonical = true }), json.encode(value, { canonical = true }), "case " .. case)
        end
        encoded_count = encoded_count + 1
      else
        self:assert_true(core.is_instance_of(text, json.EncodeError), ("case %d: %s"):format(case, tostring(text)))
      end
    end
  end
  self:assert_true(encoded_count > 1000)
end

return T
