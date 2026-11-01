local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("InterfaceTest")

--- Passes a value through untyped, so that a test can give an argument that is invalid on purpose.
---@param value any
---@return any
local function invalid(value) return value end

function T:test_conforming_class_finalises()
  local Comparable = core.interface("Comparable", { "compare" })
  local A = core.class("A", nil, { implements = { Comparable } })
  function A:compare() return 0 end
  core.finalise(A)
  self:assert_true(core.implements(A, Comparable))
  self:assert_true(core.implements(A(), Comparable))
end

function T:test_missing_method_names_class_member_and_origin()
  local Comparable = core.interface("Comparable", { "compare", "hash" })
  local A = core.class("A", nil, { implements = { Comparable } })
  function A:compare() end
  local err = self:assert_error(function() core.finalise(A) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("A", 1, true) ~= nil)
  self:assert_true(err.message:find("hash", 1, true) ~= nil)
  self:assert_true(err.message:find("Comparable", 1, true) ~= nil)
  self:assert_nil(err.message:find("compare,", 1, true))
  self:assert_equal("A", err.context.class)
  self:assert_equal("hash", err.context.missing[1].member)
  self:assert_equal("Comparable", err.context.missing[1].origin)
end

function T:test_non_function_member_does_not_satisfy_interface()
  local I = core.interface("I", { "m" })
  local A = core.class("A", nil, { implements = { I } })
  A.m = 3
  self:assert_error(function() core.finalise(A) end)
end

function T:test_method_may_come_from_trait_or_superclass()
  local I = core.interface("I", { "a", "b" })
  local Tr = core.trait("Tr", { a = function() end })
  local Base = core.class("Base")
  function Base:b() end
  core.finalise(Base)
  local C = core.class("C", Base, { traits = { Tr }, implements = { I } })
  core.finalise(C)
  self:assert_true(core.implements(C, I))
end

function T:test_interface_extends_other_interfaces()
  local Readable = core.interface("Readable", { "read" })
  local Duplex = core.interface("Duplex", { "write" }, { extends = { Readable } })
  local A = core.class("A", nil, { implements = { Duplex } })
  function A:write() end
  local err = self:assert_error(function() core.finalise(A) end)
  self:assert_true(err.message:find("read", 1, true) ~= nil)
  self:assert_true(err.message:find("Readable", 1, true) ~= nil)
  function A:read() end
  core.finalise(A)
  self:assert_true(core.implements(A, Readable))
  self:assert_true(core.implements(A, Duplex))
end

function T:test_implements_is_inherited_by_subclasses()
  local I = core.interface("I", { "m" })
  local Base = core.class("Base", nil, { implements = { I } })
  function Base:m() end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  self:assert_true(core.implements(Derived, I))
end

function T:test_class_that_does_not_declare_is_not_implementing()
  local I = core.interface("I", { "m" })
  local A = core.class("A")
  function A:m() end
  core.finalise(A)
  self:assert_false(core.implements(A, I))
end

function T:test_interface_is_frozen_and_not_instantiable()
  local I = core.interface("I", { "m" })
  self:assert_error(function() I.x = 1 end)
  self:assert_error(function() return I() end)
end

function T:test_interface_method_names_must_be_strings()
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: assign-type-mismatch
    core.interface("I", { 1 })
  end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_methods_with_non_sequence_keys_are_rejected()
  for _, methods in ipairs({
    invalid({ "a", extra = "b" }),
    invalid({ m = "x" }),
    invalid({ "a", nil, "c" }),
    invalid({ "a", [3] = "c" }),
    invalid({ [1.5] = "a" }),
  }) do
    local err = self:assert_error(function() core.interface("I", methods) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
    self:assert_true(err.message:find("list of names", 1, true) ~= nil)
  end
end

function T:test_interface_name_must_be_a_non_empty_string()
  for _, name in ipairs({ "", 42 }) do
    local err = self:assert_error(function() core.interface(invalid(name), { "m" }) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
    self:assert_true(err.message:find("interface name must be a non-empty string", 1, true) ~= nil)
  end
end

return T
