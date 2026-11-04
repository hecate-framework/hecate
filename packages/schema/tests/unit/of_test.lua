---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("SchemaOfTest")

--- A class `name` whose schema() is built by `build`, called with the sibling classes.
local function class_of(name, build)
  local C = core.class(name)
  function C.schema() return build() end
  core.finalise(C)
  return C
end

function T:test_self_reference_validates_a_tree_and_emits_a_cycle()
  local Node
  Node = class_of("Node", function()
    return schema.object({ label = schema.string(), children = schema.array(schema.of(Node)) })
  end)
  local s = schema.of(Node)
  self:assert_true((s:validate({ label = "a", children = { { label = "b", children = {} } } })))
  local ok, violations = s:validate({ label = "a", children = { { label = 1, children = {} } } })
  self:assert_false(ok)
  self:assert_equal("/children/0/label", violations[1].path)
  local doc = s:to_json_schema()
  self:assert_equal("#/$defs/Node", doc["$ref"])
  self:assert_equal("#/$defs/Node", doc["$defs"].Node.properties.children.items["$ref"])
end

function T:test_mutual_pair_and_three_cycle()
  local A, B, C
  A = class_of("A", function() return schema.object({ b = schema.optional(schema.of(B)) }) end)
  B = class_of("B", function() return schema.object({ c = schema.optional(schema.of(C)) }) end)
  C = class_of("C", function() return schema.object({ a = schema.optional(schema.of(A)) }) end)
  local s = schema.of(A)
  self:assert_true((s:validate({ b = { c = { a = { b = {} } } } })))
  self:assert_false((s:validate({ b = { c = { a = { b = { c = 3 } } } } })))
  local ok, converted = s:coerce({ b = { c = {} } })
  self:assert_true(ok)
  self:assert_not_nil(converted.b.c)
  local defs = s:to_json_schema()["$defs"]
  self:assert_equal("#/$defs/B", defs.A.properties.b["$ref"])
  self:assert_equal("#/$defs/C", defs.B.properties.c["$ref"])
  self:assert_equal("#/$defs/A", defs.C.properties.a["$ref"])
end

function T:test_resolution_is_lazy_and_memoized()
  local calls = 0
  local U = core.class("U")
  function U.schema() calls = calls + 1; return schema.object({}) end
  core.finalise(U)
  local s = schema.of(U)
  self:assert_equal(0, calls)
  s:validate({}); s:validate({}); s:to_json_schema()
  self:assert_equal(1, calls)
end

function T:test_class_without_schema_function_is_refused()
  local P = core.class("Plain")
  core.finalise(P)
  self:assert_false(pcall(function() return schema.of(P):validate({}) end))
  self:assert_false(pcall(schema.of, 42))
end

return T
