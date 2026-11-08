---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible
-- The round trip of content (review findings S14 and q1): `json.decode(text)`, `Schema:build`, `Schema:represent`,
-- `json.encode` with the canonical option gives back the canonical input, for a class that has a tagged union, a default,
-- a nullable attribute sent as an explicit `null`, an optional attribute left out, an enumeration, a nested class, arrays,
-- a map and a value class; with POST semantics (the default method, defaults filled) and with PATCH semantics (only what
-- was sent comes back, no default applied).
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaRoundTripTest")

local CANONICAL = { canonical = true }

local function define(name, build, value_kind)
  local C = value_kind and core.value_class(name) or core.class(name)
  function C.schema() return build() end
  function C:init() end
  core.finalise(C)
  return C
end

local function classes()
  local Colour = core.enumeration("RoundColour", { "red", "green" })
  local Money = define("RoundMoney", function()
    return schema.object({ amount = schema.integer({ minimum = 0 }), currency = schema.string({ min_length = 3, max_length = 3 }) })
  end, true)
  local Address = define("RoundAddress", function()
    return schema.object({ city = schema.string(), zip = schema.optional(schema.string()) })
  end)
  local Order = define("RoundOrder", function()
    return schema.object({
      id = schema.integer(),
      colour = schema.enumeration(Colour),
      shape = schema.tagged_union("kind", {
        circle = schema.object({ radius = schema.integer() }),
        square = schema.object({ side = schema.integer(), label = schema.optional(schema.string()) }),
      }),
      price = schema.of(Money),
      address = schema.of(Address),
      previous = schema.nullable(schema.of(Address)), -- required, may be null
      note = schema.optional(schema.nullable(schema.string())), -- may be absent, null or text
      nick = schema.optional(schema.string()), -- may be absent
      priority = schema.default(schema.integer(), 5),
      lines = schema.array(schema.object({ sku = schema.string(), qty = schema.integer({ minimum = 1 }) })),
      tags = schema.array(schema.string()),
      attributes = schema.map(schema.nullable(schema.string())),
    })
  end)
  return schema.of(Order)
end

--- decode, build, represent, encode.
local function round_trip(self, s, text, options)
  local ok, instance = s:build(json.decode(text), options)
  self:assert_true(ok, ok and "" or tostring(instance[1]))
  return json.encode(s:represent(instance), CANONICAL)
end

local function assert_canonical(self, text)
  self:assert_equal(text, json.encode(json.decode(text), CANONICAL), "the sample is not in canonical form")
end

local FULL = '{"address":{"city":"Paris","zip":"75001"},"attributes":{"a":"x","b":null},"colour":"green","id":7,'
  .. '"lines":[{"qty":2,"sku":"A1"},{"qty":1,"sku":"B2"}],"nick":"ada","note":null,"previous":null,'
  .. '"price":{"amount":1250,"currency":"EUR"},"priority":9,"shape":{"kind":"square","label":"big","side":4},"tags":["a","b","a"]}'

function T:test_post_round_trip_of_a_complete_document()
  local s = classes()
  assert_canonical(self, FULL)
  self:assert_equal(FULL, round_trip(self, s, FULL))
end

function T:test_post_round_trip_with_the_other_variant_a_text_note_and_a_previous_address()
  local s = classes()
  local text = '{"address":{"city":"Lyon"},"attributes":{},"colour":"red","id":1,"lines":[],"note":"hello",'
    .. '"previous":{"city":"Nice","zip":"06000"},"price":{"amount":0,"currency":"USD"},"priority":5,'
    .. '"shape":{"kind":"circle","radius":3},"tags":[]}'
  assert_canonical(self, text)
  self:assert_equal(text, round_trip(self, s, text))
end

function T:test_post_fills_the_default_and_the_result_is_a_fixed_point()
  local s = classes()
  local input = '{"address":{"city":"Lyon"},"attributes":{},"colour":"red","id":1,"lines":[],'
    .. '"previous":null,"price":{"amount":3,"currency":"USD"},"shape":{"kind":"circle","radius":3},"tags":[]}'
  local filled = '{"address":{"city":"Lyon"},"attributes":{},"colour":"red","id":1,"lines":[],"previous":null,'
    .. '"price":{"amount":3,"currency":"USD"},"priority":5,"shape":{"kind":"circle","radius":3},"tags":[]}'
  assert_canonical(self, input)
  assert_canonical(self, filled)
  self:assert_equal(filled, round_trip(self, s, input)) -- the default fills, `note` and `nick` stay absent
  self:assert_equal(filled, round_trip(self, s, filled))
end

function T:test_an_explicit_null_and_an_absent_attribute_stay_different()
  local s = classes()
  local base = '{"address":{"city":"Lyon"},"attributes":{},"colour":"red","id":1,"lines":[],%s"previous":null,'
    .. '"price":{"amount":3,"currency":"USD"},"priority":5,"shape":{"kind":"circle","radius":3},"tags":[]}'
  local with_null = base:format('"note":null,')
  local without = base:format("")
  self:assert_equal(with_null, round_trip(self, s, with_null))
  self:assert_equal(without, round_trip(self, s, without))
end

function T:test_empty_containers_keep_their_kind()
  local s = classes()
  local text = '{"address":{"city":""},"attributes":{},"colour":"red","id":0,"lines":[],"previous":null,'
    .. '"price":{"amount":0,"currency":"EUR"},"priority":0,"shape":{"kind":"circle","radius":-1},"tags":[]}'
  self:assert_equal(text, round_trip(self, s, text))
end

function T:test_patch_round_trips_only_what_was_sent()
  local s = classes()
  for _, text in ipairs({
    '{"priority":1}',
    '{"note":null}',
    '{"previous":null}',
    '{"nick":"x","tags":["z"]}',
    '{"address":{"city":"Rome"}}',
    '{"attributes":{"k":null}}',
    '{"price":{"amount":5,"currency":"GBP"}}',
    '{}',
  }) do
    assert_canonical(self, text)
    self:assert_equal(text, round_trip(self, s, text, { method = "PATCH" }), text)
  end
end

function T:test_patch_applies_no_default_and_post_requires_what_patch_may_omit()
  local s = classes()
  self:assert_equal("{}", round_trip(self, s, "{}", { method = "PATCH" }))
  local ok, violations = s:build(json.decode("{}"))
  self:assert_false(ok)
  self:assert_equal("required", violations[1].code)
end

function T:test_a_rejected_document_does_not_round_trip()
  local s = classes()
  local ok, violations = s:build(json.decode('{"id":"7"}'), { method = "PATCH" })
  self:assert_false(ok)
  self:assert_equal("/id", violations[1].path)
end

return T
