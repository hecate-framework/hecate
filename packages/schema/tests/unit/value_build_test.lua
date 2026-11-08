---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaValueBuildTest")

--- A class `name` (value class when `value`) whose schema() is built by `build`; `init` needs arguments.
local function class_of(name, build, value)
  local C = value and core.value_class(name) or core.class(name)
  function C.schema() return build() end
  function C:init(a, b) self.a = a.x; self.b = b.y end -- would fail with no argument
  core.finalise(C)
  return C
end

local function point_class()
  return class_of("VPoint", function()
    return schema.object({ x = schema.integer(), y = schema.optional(schema.integer()) })
  end, true)
end

function T:test_build_gives_a_frozen_instance_of_a_value_class()
  local Point = point_class()
  local ok, p = schema.of(Point):build({ x = 1, y = 2 })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(p, Point))
  self:assert_equal(1, p.x)
  self:assert_equal(2, p.y)
  local err = self:assert_error(function() p.x = 5 end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
end

function T:test_two_built_instances_are_equal()
  local Point = point_class()
  local s = schema.of(Point)
  local _, a = s:build({ x = 1, y = 2 })
  local _, b = s:build({ x = 1, y = 2 })
  local _, c = s:build({ x = 1, y = 3 })
  self:assert_true(a == b)
  self:assert_true(a ~= c)
end

function T:test_sent_works_on_a_value_instance()
  local Point = point_class()
  local _, p = schema.of(Point):build({ x = 1 })
  self:assert_true(schema.sent(p, "x"))
  self:assert_false(schema.sent(p, "y"))
  self:assert_nil(p.y)
end

function T:test_defaults_apply_but_are_not_sent_and_patch_has_none()
  local Page = class_of("VPage", function()
    return schema.object({ size = schema.default(schema.integer(), 10), q = schema.optional(schema.string()) })
  end, true)
  local s = schema.of(Page)
  local ok, p = s:build({})
  self:assert_true(ok)
  self:assert_equal(10, p.size)
  self:assert_false(schema.sent(p, "size"))
  local _, patched = s:build({}, { method = "PATCH" })
  self:assert_nil(patched.size)
  local _, given = s:build({ size = 3, q = "a" })
  self:assert_equal(3, given.size)
  self:assert_true(schema.sent(given, "size"))
end

function T:test_explicit_null_is_nil_and_sent()
  local N = class_of("VNull", function()
    return schema.object({ nick = schema.optional(schema.nullable(schema.string())) })
  end, true)
  local _, n = schema.of(N):build({ nick = json.null })
  self:assert_nil(n.nick)
  self:assert_true(schema.sent(n, "nick"))
end

function T:test_value_class_nested_in_an_ordinary_class()
  local Point = point_class()
  local Shape = class_of("Shape", function()
    return schema.object({ origin = schema.of(Point), others = schema.array(schema.of(Point)) })
  end, false)
  local ok, shape = schema.of(Shape):build({ origin = { x = 1 }, others = { { x = 2 }, { x = 3, y = 4 } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(shape, Shape))
  self:assert_true(core.is_instance_of(shape.origin, Point))
  shape.origin = nil -- the ordinary parent stays mutable
  self:assert_equal(3, shape.others[2].x)
  self:assert_false(pcall(function() shape.others[2].x = 9 end))
end

function T:test_ordinary_class_nested_in_a_value_class()
  local Tag = class_of("Tag", function() return schema.object({ name = schema.string() }) end, false)
  local Post = class_of("VPost", function()
    return schema.object({ tag = schema.of(Tag), tags = schema.array(schema.of(Tag)) })
  end, true)
  local ok, post = schema.of(Post):build({ tag = { name = "a" }, tags = { { name = "b" } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(post, Post))
  self:assert_true(core.is_instance_of(post.tag, Tag))
  post.tag.name = "z" -- the ordinary child stays mutable
  self:assert_equal("z", post.tag.name)
  self:assert_false(pcall(function() post.tag = nil end))
end

function T:test_value_class_nested_in_a_value_class_and_equality()
  local Point = point_class()
  local Line = class_of("VLine", function()
    return schema.object({ from = schema.of(Point), to = schema.of(Point) })
  end, true)
  local s = schema.of(Line)
  local content = { from = { x = 0 }, to = { x = 1, y = 1 } }
  local _, a = s:build(content)
  local _, b = s:build(content)
  self:assert_true(core.is_instance_of(a.from, Point))
  self:assert_true(a == b)
end

--- A frozen value object keeps its attributes in a hidden table behind `__pairs`; the native encoder follows `__pairs`
--- (OQ-94), so the built instance encodes directly (no copy made with `pairs`), as an object of its attributes.
function T:test_pairs_of_a_built_value_instance_sees_only_the_attributes_and_it_encodes_directly()
  local Point = point_class()
  local _, p = schema.of(Point):build({ x = 1, y = 2 })
  self:assert_equal('{"x":1,"y":2}', json.encode(p, { canonical = true }))
  local decoded = json.decode(json.encode(p))
  self:assert_equal(1, decoded.x)
  self:assert_equal(2, decoded.y)
  local count = 0
  for _ in pairs(p) do count = count + 1 end
  self:assert_equal(2, count)
end

function T:test_failed_build_makes_no_instance()
  local ok, violations = schema.of(point_class()):build({ y = 2 })
  self:assert_false(ok)
  self:assert_equal("required", violations[1].code)
end

return T
