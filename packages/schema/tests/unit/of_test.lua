---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("SchemaOfTest")

--- A class `name` whose schema() is built by `build`, called with the sibling classes.
local function class_of(name, build)
  local C = core.class(name, nil, { implements = { schema.Representable } })
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
  local U = core.class("U", nil, { implements = { schema.Representable } })
  function U.schema() calls = calls + 1; return schema.object({}) end
  core.finalise(U)
  local s = schema.of(U)
  self:assert_equal(0, calls)
  s:validate({}); s:validate({}); s:to_json_schema()
  self:assert_equal(1, calls)
end

function T:test_class_without_schema_function_is_refused()
  local P = core.class("Plain", nil, { implements = { schema.Representable } })
  self:assert_false(pcall(core.finalise, P))
  self:assert_false(pcall(schema.of, 42))
end

local function refusal(self, fn)
  local ok, err = pcall(fn)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  return err.message
end

function T:test_refusal_at_declaration_for_a_finalised_class_without_the_interface()
  local Bare = core.class("BareFinalised")
  function Bare.schema() return schema.object({}) end
  core.finalise(Bare)
  local message = refusal(self, function() schema.of(Bare) end)
  self:assert_equal(
    "schema.of: class BareFinalised does not declare the interface schema.Representable; declare it with "
      .. "`implements = { schema.Representable }` in the class options so that finalise checks its class-level schema()",
    message)
end

function T:test_refusal_at_first_use_for_a_class_not_yet_finalised_at_declaration()
  local Late = core.class("LateClass")
  function Late.schema() return schema.object({}) end
  local s = schema.of(Late) -- not finalised: no refusal yet
  core.finalise(Late)
  local message = refusal(self, function() s:validate({}) end)
  self:assert_true(message:find("class LateClass does not declare the interface schema.Representable", 1, true) ~= nil, message)
end

function T:test_a_class_that_declares_the_interface_before_finalisation_is_accepted()
  local Good = core.class("GoodLate", nil, { implements = { schema.Representable } })
  function Good.schema() return schema.object({ a = schema.integer() }) end
  local s = schema.of(Good)
  core.finalise(Good)
  self:assert_true((s:validate({ a = 1 })))
end

function T:test_a_conforming_finalised_class_is_accepted_and_a_subclass_inherits_the_declaration()
  local Base = class_of("ConformingBase", function() return schema.object({}) end)
  self:assert_equal("ConformingBase", schema.of(Base):to_json_schema()["$ref"]:match("[^/]+$"))
  local Child = core.class("ConformingChild", Base)
  function Child.schema() return schema.object({ b = schema.string() }) end
  core.finalise(Child)
  self:assert_true((schema.of(Child):validate({ b = "x" })))
end

function T:test_a_table_that_is_not_a_class_is_refused()
  local message = refusal(self, function() schema.of({ schema = function() return schema.object({}) end }) end)
  self:assert_true(message:find("schema.Representable", 1, true) ~= nil, message)
end

function T:test_module_name_form_refuses_a_non_conforming_class_and_accepts_a_conforming_one()
  local Bare = core.class("ModBare")
  function Bare.schema() return schema.object({}) end
  core.finalise(Bare)
  local Good = class_of("ModGood", function() return schema.object({}) end)
  package.loaded["of_test.bare"] = Bare
  package.loaded["of_test.good"] = Good
  local ok, err = pcall(function() return schema.of("of_test.bare"):validate({}) end)
  self:assert_false(ok)
  self:assert_true(err.message:find("class ModBare does not declare the interface schema.Representable", 1, true) ~= nil, err.message)
  self:assert_true((schema.of("of_test.good"):validate({})))
  package.loaded["of_test.bare"], package.loaded["of_test.good"] = nil, nil
end

return T
