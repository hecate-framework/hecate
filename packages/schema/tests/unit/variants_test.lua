---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests index violations they just asserted exist
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaVariantsTest")

function T:raises(fn, ...)
  local args = table.pack(...)
  self:assert_false(pcall(fn, table.unpack(args, 1, args.n)))
end

local function shape()
  return schema.tagged_union("kind", {
    circle = schema.object({ radius = schema.number({ minimum = 0 }) }),
    square = schema.object({ side = schema.integer() }),
  })
end

function T:test_tagged_union_accepts_each_variant()
  self:assert_true((shape():validate({ kind = "circle", radius = 1.5 })))
  self:assert_true((shape():validate({ kind = "square", side = 2 })))
end

function T:test_tagged_union_reports_the_variant_violations_with_paths()
  local ok, violations = shape():validate({ kind = "square", side = "x", extra = 1 })
  self:assert_false(ok)
  self:assert_equal(2, #violations)
  self:assert_equal("/side", violations[1].path)
  self:assert_equal("type", violations[1].code)
  self:assert_equal("/extra", violations[2].path)
  self:assert_equal("additional_properties", violations[2].code)
end

function T:test_tagged_union_reports_a_missing_or_unknown_tag()
  local ok, violations = shape():validate({ radius = 1 })
  self:assert_false(ok)
  self:assert_equal("/kind", violations[1].path)
  self:assert_equal("required", violations[1].code)
  for _, value in ipairs({ "triangle", 1, true }) do
    ok, violations = shape():validate({ kind = value })
    self:assert_false(ok)
    self:assert_equal(1, #violations)
    self:assert_equal("/kind", violations[1].path)
    self:assert_equal("tagged_union", violations[1].code)
  end
  ok, violations = shape():validate("circle")
  self:assert_equal("type", violations[1].code)
  self:assert_false((shape():validate(json.null)))
end

function T:test_tagged_union_nested_path_is_escaped()
  local s = schema.object({ shapes = schema.array(shape()) })
  local ok, violations = s:validate({ shapes = { { kind = "square", side = 1 }, { kind = "square" } } })
  self:assert_false(ok)
  self:assert_equal("/shapes/1/side", violations[1].path)
end

function T:test_tagged_union_declaration_is_checked()
  local function refused(...) self:raises(schema.tagged_union, ...) end
  refused("kind", {})
  refused("", { a = schema.object({}) })
  refused("kind", { a = schema.string() })
  refused("kind", { a = schema.object({ kind = schema.string() }) })
  refused("kind", { [1] = schema.object({}) })
  refused(1, { a = schema.object({}) })
end

function T:test_tagged_union_is_immutable()
  local s = shape()
  self:assert_error(function() s.kind = "x" end, ".")
  self:assert_equal("tagged_union", s.kind)
end

function T:test_tagged_union_coerces_the_selected_variant()
  local ok, value = shape():coerce({ kind = "square", side = "4" })
  self:assert_true(ok)
  self:assert_equal(4, value.side)
  ok = shape():coerce({ kind = "square", side = "x" })
  self:assert_false(ok)
  self:assert_false((shape():coerce({ kind = "nope" })))
end

function T:test_default_makes_a_property_optional_and_applies_in_coerce()
  local s = schema.object({ name = schema.string(), level = schema.default(schema.integer(), 3) })
  self:assert_true((s:validate({ name = "x" })))
  self:assert_true((s:validate({ name = "x", level = 5 })))
  self:assert_false((s:validate({ name = "x", level = "5" })))
  local input = { name = "x" }
  local ok, value = s:coerce(input)
  self:assert_true(ok)
  self:assert_equal(3, value.level)
  self:assert_equal(nil, input.level) -- the input is never modified
  ok, value = s:coerce({ name = "x", level = "7" })
  self:assert_equal(7, value.level)
end

function T:test_default_does_not_apply_in_validate()
  local s = schema.object({ level = schema.default(schema.integer(), 3) })
  local value = {}
  self:assert_true((s:validate(value)))
  self:assert_equal(nil, value.level)
end

function T:test_default_of_a_table_is_a_fresh_copy()
  local s = schema.object({ tags = schema.default(schema.array(schema.string()), { "a" }) })
  local _, first = s:coerce({})
  first.tags[1] = "changed"
  local _, second = s:coerce({})
  self:assert_equal("a", second.tags[1])
end

function T:test_default_is_checked_at_declaration()
  self:raises(schema.default, schema.integer(), "x")
  self:raises(schema.default, schema.integer({ minimum = 5 }), 1)
  self:raises(schema.default, schema.optional(schema.integer()), 1)
  self:raises(schema.default, schema.default(schema.integer(), 1), 1)
  self:raises(schema.optional, schema.default(schema.integer(), 1))
  self:raises(schema.default, "integer", 1)
  self:raises(schema.default, schema.integer())
  self:assert_equal(json.null, select(2, schema.object({ a = schema.default(schema.nullable(schema.integer()), json.null) }):coerce({})).a)
end

function T:test_default_at_top_level_replaces_an_absent_value()
  local s = schema.default(schema.integer(), 9)
  local ok, value = s:coerce(nil)
  self:assert_true(ok)
  self:assert_equal(9, value)
  self:assert_equal(4, select(2, s:coerce("4")))
end

return T
