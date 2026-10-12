local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("TraitTest")

local function expect_conformance(self, fn)
  local err = self:assert_error(fn)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  return err
end

function T:test_trait_methods_are_composed_into_class()
  local Timestamped = core.trait("Timestamped", {
    touch = function(self) self.updated = true end,
  })
  local A = core.class("A", nil, { traits = { Timestamped } })
  core.finalise(A)
  local a = A()
  a:touch()
  self:assert_true(a.updated)
  self:assert_true(rawget(A, "touch") ~= nil)
end

function T:test_class_method_overrides_trait_method()
  local Tr = core.trait("Tr", { who = function() return "trait" end })
  local A = core.class("A", nil, { traits = { Tr } })
  function A:who() return "class" end
  core.finalise(A)
  self:assert_equal("class", A():who())
end

function T:test_trait_method_overrides_inherited_method()
  local Tr = core.trait("Tr", { who = function() return "trait" end })
  local Base = core.class("Base")
  function Base:who() return "base" end
  core.finalise(Base)
  local A = core.class("A", Base, { traits = { Tr } })
  core.finalise(A)
  self:assert_equal("trait", A():who())
end

function T:test_conflicting_traits_are_an_error_naming_everything()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local A = core.class("A", nil, { traits = { T1, T2 } })
  local err = expect_conformance(self, function() core.finalise(A) end)
  self:assert_true(err.message:find("A", 1, true) ~= nil)
  self:assert_true(err.message:find("m", 1, true) ~= nil)
  self:assert_true(err.message:find("T1", 1, true) ~= nil)
  self:assert_true(err.message:find("T2", 1, true) ~= nil)
  self:assert_equal("A", err.context.class)
end

function T:test_conflict_resolved_by_class_method()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local A = core.class("A", nil, { traits = { T1, T2 } })
  function A:m() return 3 end
  core.finalise(A)
  self:assert_equal(3, A():m())
end

function T:test_conflict_resolved_by_exclusion()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local A = core.class("A", nil, { traits = { T1, { T2, exclude = { "m" } } } })
  core.finalise(A)
  self:assert_equal(1, A():m())
end

function T:test_conflict_resolved_by_alias_keeps_both()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local A = core.class("A", nil, {
    traits = { T1, { T2, exclude = { "m" }, alias = { m = "m2" } } },
  })
  core.finalise(A)
  local a = A()
  self:assert_equal(1, a:m())
  self:assert_equal(2, a:m2())
end

function T:test_alias_keeps_original_name_unless_excluded()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local A = core.class("A", nil, { traits = { { T1, alias = { m = "n" } } } })
  core.finalise(A)
  self:assert_equal(1, A():m())
  self:assert_equal(1, A():n())
end

function T:test_excluding_an_unknown_method_is_an_error()
  local T1 = core.trait("T1", { m = function() end })
  local A = core.class("A", nil, { traits = { { T1, exclude = { "nope" } } } })
  local err = expect_conformance(self, function() core.finalise(A) end)
  self:assert_true(err.message:find("nope", 1, true) ~= nil)
end

function T:test_same_trait_reached_twice_is_not_a_conflict()
  local Base = core.trait("Base", { m = function() return 1 end })
  local T1 = core.trait("T1", { n = function() return 1 end }, { traits = { Base } })
  local T2 = core.trait("T2", { o = function() return 1 end }, { traits = { Base } })
  local A = core.class("A", nil, { traits = { T1, T2 } })
  core.finalise(A)
  self:assert_equal(1, A():m())
end

function T:test_traits_compose_traits_and_detect_conflicts_at_definition()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local err = expect_conformance(self, function()
    core.trait("T3", {}, { traits = { T1, T2 } })
  end)
  self:assert_true(err.message:find("T3", 1, true) ~= nil)
end

function T:test_trait_own_method_resolves_composition_conflict()
  local T1 = core.trait("T1", { m = function() return 1 end })
  local T2 = core.trait("T2", { m = function() return 2 end })
  local T3 = core.trait("T3", { m = function() return 3 end }, { traits = { T1, T2 } })
  local A = core.class("A", nil, { traits = { T3 } })
  core.finalise(A)
  self:assert_equal(3, A():m())
end

function T:test_required_methods_must_be_provided()
  local Tr = core.trait("Tr", { go = function(self) return self:step() end }, {
    requires = { "step" },
  })
  local A = core.class("A", nil, { traits = { Tr } })
  local err = expect_conformance(self, function() core.finalise(A) end)
  self:assert_true(err.message:find("step", 1, true) ~= nil)
  self:assert_true(err.message:find("Tr", 1, true) ~= nil)
  local B = core.class("B", nil, { traits = { Tr } })
  function B:step() return "ok" end
  core.finalise(B)
  self:assert_equal("ok", B():go())
end

function T:test_requirement_can_be_met_by_inherited_method_or_other_trait()
  local Tr = core.trait("Tr", {}, { requires = { "step" } })
  local Provider = core.trait("Provider", { step = function() end })
  local A = core.class("A", nil, { traits = { Tr, Provider } })
  core.finalise(A)
  local Base = core.class("Base")
  function Base:step() end
  core.finalise(Base)
  local B = core.class("B", Base, { traits = { Tr } })
  core.finalise(B)
end

function T:test_failed_finalisation_leaves_class_unchanged()
  local T1 = core.trait("T1", { m = function() end })
  local T2 = core.trait("T2", { m = function() end })
  local A = core.class("A", nil, { traits = { T1, T2 } })
  pcall(core.finalise, A)
  self:assert_nil(rawget(A, "m"))
  self:assert_false(core.is_finalised(A))
end

function T:test_origin_of_members()
  local Tr = core.trait("Tr", { t = function() end })
  local Base = core.class("Base")
  function Base:b() end
  core.finalise(Base)
  local A = core.class("A", Base, { traits = { Tr } })
  function A:a() end
  core.finalise(A)
  self:assert_equal("class A", core.origin(A, "a"))
  self:assert_equal("trait Tr", core.origin(A, "t"))
  self:assert_equal("class Base", core.origin(A, "b"))
  self:assert_nil(core.origin(A, "zzz"))
end

function T:test_trait_methods_must_be_functions()
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: assign-type-mismatch
    core.trait("Bad", { x = 1 })
  end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_trait_is_not_instantiable_and_is_frozen()
  local Tr = core.trait("Tr", { m = function() end })
  self:assert_error(function() return Tr() end)
  self:assert_error(function() Tr.x = 1 end)
end

return T
