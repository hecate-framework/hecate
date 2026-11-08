---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- OQ-99 (3): a union must not contain null; `nullable` is the only way to accept null.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaUnionNullTest")

local function refused_message(self, fn)
  local err = self:assert_error(fn)
  self:assert_equal("hecate.core.ArgumentError", err.code)
  return err.message
end

function T:test_a_null_alternative_is_refused_with_the_remedy()
  local message = refused_message(self, function() return schema.union({ schema.string(), schema.null() }) end)
  self:assert_true(message:find("alternative 2 is a null schema", 1, true) ~= nil)
  self:assert_true(message:find("nullable(union(...))", 1, true) ~= nil)
end

function T:test_a_nullable_alternative_is_refused()
  local message = refused_message(self, function()
    return schema.union({ schema.nullable(schema.integer()), schema.string() })
  end)
  self:assert_true(message:find("alternative 1 is a nullable schema", 1, true) ~= nil)
end

function T:test_the_refusal_sees_through_named_optional_and_default()
  local function refused(inner) refused_message(self, function() return schema.union({ schema.string(), inner }) end) end
  refused(schema.named("MaybeNull", schema.null()))
  refused(schema.named("MaybeInt", schema.nullable(schema.integer())))
  refused(schema.optional(schema.nullable(schema.integer())))
  refused(schema.default(schema.nullable(schema.integer()), 1))
  refused(schema.optional(schema.named("N", schema.null())))
end

function T:test_a_literal_null_alternative_is_refused_with_the_kind()
  local message = refused_message(self, function() return schema.union({ schema.string(), schema.literal(json.null) }) end)
  self:assert_true(message:find("alternative 2 is a literal null", 1, true) ~= nil)
  self:assert_true(message:find("nullable(union(...))", 1, true) ~= nil)
end

function T:test_an_enumeration_containing_null_is_refused_with_the_kind()
  local message = refused_message(self, function()
    return schema.union({ schema.integer(), schema.enumeration({ "a", json.null }) })
  end)
  self:assert_true(message:find("alternative 2 is an enumeration containing null", 1, true) ~= nil)
  self:assert_true(message:find("nullable(union(...))", 1, true) ~= nil)
  local first = refused_message(self, function() return schema.union({ schema.enumeration({ json.null, 1 }), schema.string() }) end)
  self:assert_true(first:find("alternative 1 is an enumeration containing null", 1, true) ~= nil)
end

function T:test_a_literal_null_or_enumeration_is_refused_under_named_optional_and_default()
  local function refused(inner) refused_message(self, function() return schema.union({ schema.string(), inner }) end) end
  for _, make in ipairs({
    function() return schema.literal(json.null) end,
    function() return schema.enumeration({ "a", json.null }) end,
  }) do
    refused(schema.named("N", make()))
    refused(schema.optional(make()))
    refused(schema.default(make(), json.null))
    refused(schema.optional(schema.named("N", make())))
  end
end

function T:test_constants_that_are_not_null_are_accepted_in_a_union()
  local s = schema.union({ schema.literal("a"), schema.enumeration({ "b", 1, false }), schema.named("L", schema.literal(2)) })
  self:assert_true((s:validate("b")))
  self:assert_false((s:validate(json.null)))
end

function T:test_a_literal_null_and_such_an_enumeration_stay_allowed_as_plain_properties()
  local s = schema.object({ a = schema.literal(json.null), b = schema.enumeration({ "x", json.null }) })
  self:assert_true((s:validate({ a = json.null, b = json.null })))
  self:assert_true((s:validate({ a = json.null, b = "x" })))
  self:assert_false((s:validate({ a = 1, b = "x" })))
end

function T:test_a_nullable_union_of_constants_round_trips()
  local s = schema.nullable(schema.union({ schema.literal("a"), schema.enumeration({ "b", "c" }) }))
  self:assert_true((s:validate(json.null)))
  self:assert_true((s:validate("c")))
  self:assert_false((s:validate("d")))
end

function T:test_the_refusal_is_a_declaration_error_not_a_violation()
  local err = self:assert_error(function() return schema.union({ schema.null(), schema.string() }) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_an_ordinary_union_and_any_are_accepted()
  local ordinary = schema.union({ schema.string(), schema.integer(), schema.named("Flag", schema.boolean()) })
  self:assert_true((ordinary:validate("x")))
  self:assert_false((ordinary:validate(json.null)))
  local with_any = schema.union({ schema.string(), schema.any() }) -- an explicit, different choice
  self:assert_true((with_any:validate(json.null)))
  self:assert_true((schema.union({ schema.optional(schema.string()), schema.integer() }):validate("x")))
end

function T:test_a_union_property_that_is_not_nullable_rejects_null()
  local s = schema.object({ v = schema.union({ schema.string(), schema.integer() }) })
  local ok, violations = s:validate({ v = json.null })
  self:assert_false(ok)
  self:assert_equal("/v", violations[1].path)
end

function T:test_nullable_union_validates()
  local s = schema.object({ v = schema.nullable(schema.union({ schema.string(), schema.integer() })) })
  self:assert_true((s:validate({ v = json.null })))
  self:assert_true((s:validate({ v = "x" })))
  self:assert_true((s:validate({ v = 3 })))
  self:assert_false((s:validate({ v = true })))
end

function T:test_nullable_union_coerces_and_never_coerces_text_to_null()
  local s = schema.object({ v = schema.nullable(schema.union({ schema.integer(), schema.boolean() })) })
  local ok, value = s:coerce({ v = "12" })
  self:assert_true(ok)
  self:assert_equal(12, value.v)
  local ok_null, kept = s:coerce({ v = json.null })
  self:assert_true(ok_null)
  self:assert_equal(json.null, kept.v)
  self:assert_false((s:coerce({ v = "null" })))
end

function T:test_nullable_union_builds_and_keeps_null()
  local s = schema.object({ v = schema.nullable(schema.union({ schema.string(), schema.integer() })) })
  local ok, built = s:build(json.decode('{"v":null}'))
  self:assert_true(ok)
  self:assert_equal(json.null, built.v)
  local _, text = s:build(json.decode('{"v":7}'))
  self:assert_equal(7, text.v)
end

function T:test_nullable_union_represent_round_trips_an_explicit_null()
  local Thing = core.class("UnionNullThing", nil, { implements = { schema.Representable } })
  function Thing.schema()
    return schema.object({ v = schema.nullable(schema.union({ schema.string(), schema.integer() })) })
  end
  function Thing:init() end
  core.finalise(Thing)
  local s = schema.of(Thing)
  for _, content in ipairs({ '{"v":null}', '{"v":"x"}', '{"v":4}' }) do
    local ok, instance = s:build(json.decode(content))
    self:assert_true(ok)
    self:assert_equal(content, json.encode(s:represent(instance)))
  end
  -- a hand-set null stays null too
  local plain = schema.object({ v = schema.nullable(schema.union({ schema.string(), schema.integer() })) })
    :represent({ v = json.null })
  self:assert_equal('{"v":null}', json.encode(plain))
end

function T:test_nullable_union_is_any_of_with_the_null_type()
  local doc = schema.nullable(schema.union({ schema.string(), schema.integer() })):to_json_schema()
  self:assert_equal(2, #doc.anyOf)
  self:assert_equal("null", doc.anyOf[2].type)
end

return T
