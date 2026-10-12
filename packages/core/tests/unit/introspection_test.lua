local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("IntrospectionTest")

function T:test_name_superclass_traits_interfaces()
  local I = core.interface("I", {})
  local Tr = core.trait("Tr", {})
  local Base = core.class("Base")
  core.finalise(Base)
  local A = core.class("A", Base, { traits = { Tr }, implements = { I } })
  core.finalise(A)
  self:assert_equal("A", core.name(A))
  self:assert_equal("Tr", core.name(Tr))
  self:assert_equal("I", core.name(I))
  self:assert_equal("A", core.name(A()))
  self:assert_true(core.superclass(A) == Base)
  self:assert_nil(core.superclass(Base))
  self:assert_true(core.traits(A)[1] == Tr)
  self:assert_true(core.interfaces(A)[1] == I)
  self:assert_equal(0, #core.traits(Base))
end

function T:test_listings_are_copies()
  local Tr = core.trait("Tr", {})
  local A = core.class("A", nil, { traits = { Tr } })
  core.finalise(A)
  core.traits(A)[1] = nil
  self:assert_equal(1, #core.traits(A))
end

function T:test_is_instance_of()
  local Base = core.class("Base")
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  local Other = core.class("Other")
  core.finalise(Other)
  local d = Derived()
  self:assert_true(core.is_instance_of(d, Derived))
  self:assert_true(core.is_instance_of(d, Base))
  self:assert_false(core.is_instance_of(d, Other))
  self:assert_false(core.is_instance_of(Base(), Derived))
  self:assert_false(core.is_instance_of(3, Base))
  self:assert_false(core.is_instance_of({}, Base))
  self:assert_false(core.is_instance_of(nil, Base))
end

function T:test_implements_accepts_traits()
  local Tr = core.trait("Tr", { m = function() end })
  local Outer = core.trait("Outer", {}, { traits = { Tr } })
  local A = core.class("A", nil, { traits = { Outer } })
  core.finalise(A)
  self:assert_true(core.implements(A, Outer))
  self:assert_true(core.implements(A, Tr))
end

function T:test_kind_predicates()
  local A = core.class("A")
  local Tr = core.trait("Tr", {})
  local I = core.interface("I", {})
  self:assert_true(core.is_class(A))
  self:assert_false(core.is_class(Tr))
  self:assert_true(core.is_trait(Tr))
  self:assert_true(core.is_interface(I))
  self:assert_false(core.is_interface({}))
  self:assert_false(core.is_class(nil))
end

function T:test_class_of()
  local A = core.class("A")
  core.finalise(A)
  self:assert_true(core.class_of(A()) == A)
  self:assert_nil(core.class_of({}))
end

function T:test_name_of_unknown_value_is_an_error()
  local err = self:assert_error(function() core.name({}) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

return T
