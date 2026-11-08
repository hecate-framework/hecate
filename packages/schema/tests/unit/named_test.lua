---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests index violations they just asserted exist
local test = require("harness.test")
local json = require("hecate.json")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("SchemaNamedTest")

local function user()
  return schema.named("User", schema.object({ id = schema.integer(), name = schema.string() }))
end

function T:test_named_validates_like_its_schema()
  self:assert_true((user():validate({ id = 1, name = "a" })))
  local ok, violations = user():validate({ id = "x", name = "a" })
  self:assert_false(ok)
  self:assert_equal("/id", violations[1].path)
end

function T:test_named_is_emitted_once_in_defs_and_referenced()
  local s = schema.object({ owner = user(), members = schema.array(user()) })
  local doc = s:to_json_schema()
  self:assert_equal("#/$defs/User", doc.properties.owner["$ref"])
  self:assert_equal("#/$defs/User", doc.properties.members.items["$ref"])
  self:assert_equal("object", doc["$defs"].User.type)
end

function T:test_named_root_is_a_reference()
  local doc = user():to_json_schema()
  self:assert_equal("#/$defs/User", doc["$ref"])
  self:assert_equal("object", doc["$defs"].User.type)
end

function T:test_two_names_may_share_a_definition_only_when_equal()
  local a = schema.named("T", schema.string())
  local b = schema.named("T", schema.integer())
  local ok = pcall(function() return schema.object({ a = a, b = b }):to_json_schema() end)
  self:assert_false(ok)
  self:assert_true(pcall(function() return schema.object({ a = a, b = schema.named("T", schema.string()) }):to_json_schema() end))
end

--- A class `name` whose schema() returns `body`.
local function class_named(name, body)
  local C = core.class(name, nil, { implements = { schema.Representable } })
  function C.schema() return body end
  core.finalise(C)
  return C
end

function T:test_inline_name_equal_to_a_class_name_with_another_body_is_refused()
  local User = class_named("User", schema.object({ email = schema.string() }))
  local s = schema.object({ inline = user(), bound = schema.of(User) })
  local ok, err = pcall(function() return s:to_json_schema() end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  self:assert_true(err.message:find("User", 1, true) ~= nil)
  self:assert_true(err.message:find("one comes from a class", 1, true) ~= nil)
  self:assert_true(err.message:find("one from named", 1, true) ~= nil)
  self:assert_equal("User", err.context.name)
end

function T:test_inline_name_equal_to_a_class_name_with_the_same_body_shares_one_definition()
  local body = schema.object({ id = schema.integer(), name = schema.string() })
  local User = class_named("User", body)
  local doc = schema.object({ inline = user(), bound = schema.of(User) }):to_json_schema()
  self:assert_equal("#/$defs/User", doc.properties.inline["$ref"])
  self:assert_equal("#/$defs/User", doc.properties.bound["$ref"])
  local count = 0
  for _ in pairs(doc["$defs"]) do count = count + 1 end
  self:assert_equal(1, count)
end

function T:test_a_class_is_emitted_under_its_class_name_without_declaration()
  local Pet = class_named("Pet", schema.object({ name = schema.string() }))
  local doc = schema.of(Pet):to_json_schema()
  self:assert_equal("#/$defs/Pet", doc["$ref"])
  self:assert_equal("object", doc["$defs"].Pet.type)
end

function T:test_a_schema_without_name_and_class_is_inlined()
  local doc = schema.object({ a = schema.object({ b = schema.string() }), c = schema.array(schema.integer()) }):to_json_schema()
  self:assert_equal(nil, doc["$defs"])
  self:assert_equal("object", doc.properties.a.type)
  self:assert_equal("integer", doc.properties.c.items.type)
end

function T:test_the_collision_message_for_two_named_says_so()
  local ok, err = pcall(function()
    return schema.object({ a = schema.named("T", schema.string()), b = schema.named("T", schema.integer()) }):to_json_schema()
  end)
  self:assert_false(ok)
  self:assert_true(err.message:find("both come from named", 1, true) ~= nil)
end

function T:test_named_declaration_is_checked()
  self:assert_false(pcall(schema.named, "", schema.string()))
  self:assert_false(pcall(schema.named, "a b", schema.string()))
  self:assert_false(pcall(schema.named, "User", "x"))
  self:assert_false(pcall(schema.named, "User", user()))
end

function T:test_named_coerces_like_its_schema()
  local ok, value = schema.named("Count", schema.integer()):coerce("42")
  self:assert_true(ok)
  self:assert_equal(42, value)
end

function T:test_any_accepts_every_json_value()
  for _, v in ipairs({ 1, "a", true, json.null, {}, { 1 } }) do self:assert_true((schema.any():validate(v))) end
  local doc = schema.any():to_json_schema()
  doc["$schema"] = nil
  self:assert_equal(nil, next(doc))
end

function T:test_null_accepts_only_json_null()
  self:assert_true((schema.null():validate(json.null)))
  self:assert_false((schema.null():validate("null")))
  self:assert_false((schema.null():validate(false)))
  self:assert_equal("null", schema.null():to_json_schema().type)
end

return T
