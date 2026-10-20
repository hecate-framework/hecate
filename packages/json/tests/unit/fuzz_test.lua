-- Differential fuzzing of the native backend against the reference backend: mutations of valid texts (the
-- built-in seeds and, when downloaded, the JSONTestSuite files) must give the same verdict, value and failure
-- on both, and a decoded value must encode to the same text on both and decode back to itself.
-- Default: a fixed seed and a fixed number of iterations (a regression test). For a longer search:
--   HECATE_FUZZ_SECONDS=60 HECATE_FUZZ_SEED=1234 lua tools/run.lua test json
-- A mismatch names the seed and the text, so that it can be replayed and added to the fixed corpus.
local test = require("harness.test")
local reference = require("hecate.json.internal.reference")
local markers = require("hecate.json.internal.markers")
local T = test.Case("JsonFuzzTest")

local built, native = pcall(require, "hecate.json.native")
local built_encoder, encoder = pcall(require, "hecate.json.encoder_native")

local OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024 }
local ENCODE_OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = false, rfc8785 = false }
local ITERATIONS = 4000

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."

function T:set_up()
  if not built then
    if (os.getenv("CI") and package.config:sub(1, 1) == "/") then self:fail("hecate.json.native is not built (lua tools/run.lua build-native json)") end
    io.stderr:write("# skipped: hecate.json.native is not built\n")
    self.skipped = true
    return
  end
  if built_encoder then encoder.bind(markers) end
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

-- Returns a description of the first disagreement on `text`, or nil.
local function disagreement(text)
  local want, want_failure = reference.decode(text, OPTIONS)
  local got, got_failure = native.decode(text, OPTIONS)
  if want_failure or got_failure then
    if not (want_failure and got_failure) then return "verdict differs" end
    if want_failure.reason ~= got_failure.reason or want_failure.offset ~= got_failure.offset
      or want_failure.message ~= got_failure.message then
      return "failure differs: " .. tostring(want_failure.message) .. " / " .. tostring(got_failure.message)
    end
    return nil
  end
  if not same(want, got) then return "values differ" end
  local text_ref = reference.encode(want, ENCODE_OPTIONS)
  if text_ref ~= nil and built_encoder then
    local text_native = encoder.encode(want, ENCODE_OPTIONS)
    if text_native ~= nil and text_native ~= text_ref then return "encoders differ" end
  end
  if text_ref ~= nil then
    local again = reference.decode(text_ref, OPTIONS)
    if not same(want, again) then return "the encoded text does not decode back to the value" end
  end
  return nil
end

function T:test_mutated_texts_agree_on_both_backends()
  if self.skipped then return end
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
    local problem = disagreement(text)
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

return T
