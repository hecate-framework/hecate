local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("ClassTest")

function T:test_instantiation_calls_init()
  local Point = core.class("Point")
  function Point:init(x, y) self.x, self.y = x, y end
  core.finalise(Point)
  local p = Point(1, 2)
  self:assert_equal(1, p.x)
  self:assert_equal(2, p.y)
end

function T:test_methods_are_found_on_instances()
  local A = core.class("A")
  function A:hello() return "hello " .. self.who end
  core.finalise(A)
  local a = A()
  a.who = "world"
  self:assert_equal("hello world", a:hello())
end

function T:test_instance_is_not_constructible_before_finalisation()
  local A = core.class("A")
  local err = self:assert_error(function() return A() end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("A", 1, true) ~= nil)
end

function T:test_finalise_returns_class_and_is_idempotent()
  local A = core.class("A")
  self:assert_true(core.finalise(A) == A)
  self:assert_true(core.finalise(A) == A)
end

function T:test_single_table_access_after_finalisation()
  -- invariant: methods are flattened into the class table
  local Base = core.class("Base")
  function Base:greet() return "base" end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  self:assert_true(rawget(Derived, "greet") == Base.greet)
  self:assert_true(rawget(Derived, "__index") == Derived)
  local d = Derived()
  self:assert_equal("base", d:greet())
  self:assert_true(getmetatable(d) == Derived)
end

function T:test_subclass_overrides_and_calls_super()
  local Base = core.class("Base")
  function Base:init(n) self.n = n end
  function Base:describe() return "base" .. self.n end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  function Derived:init(n, m)
    core.superclass(Derived).init(self, n)
    self.m = m
  end
  function Derived:describe() return "derived+" .. core.superclass(Derived).describe(self) end
  core.finalise(Derived)
  local d = Derived(1, 2)
  self:assert_equal(2, d.m)
  self:assert_equal("derived+base1", d:describe())
end

function T:test_parent_must_be_finalised_first()
  local Base = core.class("Base")
  local Derived = core.class("Derived", Base)
  local err = self:assert_error(function() core.finalise(Derived) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("Base", 1, true) ~= nil)
  self:assert_true(err.message:find("Derived", 1, true) ~= nil)
end

function T:test_parent_must_be_a_class()
  local err = self:assert_error(function() core.class("X", {}) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_name_must_be_a_string()
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: param-type-mismatch
    core.class(42)
  end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_finalised_class_rejects_new_members()
  local A = core.class("A")
  core.finalise(A)
  local err = self:assert_error(function() A.late = function() end end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
end

function T:test_static_members_are_inherited()
  local Base = core.class("Base")
  Base.LIMIT = 10
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  self:assert_equal(10, Derived.LIMIT)
end

function T:test_index_fallback_applies_after_flattened_lookup()
  local A = core.class("A")
  function A:known() return "known" end
  A.__index = function(_, key) return "fallback:" .. key end
  core.finalise(A)
  local a = A()
  self:assert_equal("known", a:known())
  self:assert_equal("fallback:missing", a.missing)
  self:assert_true(rawget(A, "__index") == A)
end

function T:test_index_fallback_is_inherited()
  local A = core.class("A")
  A.__index = function(_, key) return "fb:" .. key end
  core.finalise(A)
  local B = core.class("B", A)
  core.finalise(B)
  self:assert_equal("fb:x", B().x)
end

-- metamethod inheritance matrix ------------------------------------------------

function T:test_metamethods_are_inherited()
  local Base = core.class("Base")
  function Base:init(v) self.v = v end
  function Base.__tostring(self) return "Base(" .. self.v .. ")" end
  function Base.__eq(a, b) return a.v == b.v end
  function Base.__lt(a, b) return a.v < b.v end
  function Base.__le(a, b) return a.v <= b.v end
  function Base.__len(self) return self.v end
  function Base.__call(self, x) return self.v + x end
  function Base.__concat(a, b) return tostring(a) .. "|" .. tostring(b) end
  function Base.__add(a, b) return a.v + b.v end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  local a, b, c = Derived(1), Derived(2), Derived(1)
  self:assert_equal("Base(1)", tostring(a))
  self:assert_true(a == c)
  self:assert_false(a == b)
  self:assert_true(a < b)
  self:assert_true(a <= c)
  self:assert_equal(2, #b)
  self:assert_equal(12, b(10))
  self:assert_equal("Base(1)|Base(2)", a .. b)
  self:assert_equal(3, a + b)
end

function T:test_metamethod_override_in_subclass()
  local Base = core.class("Base")
  function Base.__tostring() return "base" end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  function Derived.__tostring() return "derived" end
  core.finalise(Derived)
  self:assert_equal("derived", tostring(Derived()))
  self:assert_equal("base", tostring(Base()))
end

function T:test_close_is_inherited_and_runs_on_scope_exit()
  local closed = {}
  local Resource = core.class("Resource")
  function Resource:init(label) self.label = label end
  function Resource:__close() closed[#closed + 1] = self.label end
  core.finalise(Resource)
  local Connection = core.class("Connection", Resource)
  core.finalise(Connection)
  do
    local a <close> = Connection("a")
    local b <close> = Resource("b")
    self:assert_equal(0, #closed)
  end
  self:assert_equal("b", closed[1])
  self:assert_equal("a", closed[2])
end

function T:test_close_runs_when_scope_is_left_by_error()
  local closed = false
  local R = core.class("R")
  function R:__close() closed = true end
  core.finalise(R)
  pcall(function()
    local r <close> = R()
    error("boom")
  end)
  self:assert_true(closed)
end

function T:test_index_and_name_are_not_copied_from_parent()
  local Base = core.class("Base")
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  self:assert_true(rawget(Derived, "__index") == Derived)
  self:assert_equal("Derived", rawget(Derived, "__name"))
end

-- members provided by an index fallback ----------------------------------------

local function fallback_class(name, parent, options)
  local C = core.class(name, parent, options)
  C.__index = function(_, key) return "fb:" .. key end
  return C
end

function T:test_declared_fallback_members_satisfy_an_interface()
  local I = core.interface("I", { "compare" })
  local A = fallback_class("A", nil, { implements = { I }, fallback_provides = { "compare" } })
  core.finalise(A)
  self:assert_true(core.implements(A, I))
  self:assert_nil(rawget(A, "compare"))
  self:assert_equal("fb:compare", A().compare)
end

function T:test_declared_fallback_members_satisfy_trait_requires()
  local Tr = core.trait("Tr", {}, { requires = { "step" } })
  local A = fallback_class("A", nil, { traits = { Tr }, fallback_provides = { "step" } })
  core.finalise(A)
  self:assert_nil(rawget(A, "step"))
end

function T:test_unlisted_missing_members_still_fail()
  local I = core.interface("I", { "compare", "hash" })
  local A = fallback_class("A", nil, { implements = { I }, fallback_provides = { "compare" } })
  local err = self:assert_error(function() core.finalise(A) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("hash", 1, true) ~= nil)
  self:assert_equal(1, #err.context.missing)
end

function T:test_fallback_declaration_without_fallback_is_an_error()
  local A = core.class("A", nil, { fallback_provides = { "compare" } })
  local err = self:assert_error(function() core.finalise(A) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("compare", 1, true) ~= nil)
  self:assert_true(err.message:find("A", 1, true) ~= nil)
end

function T:test_fallback_declaration_is_inherited()
  local I = core.interface("I", { "compare" })
  local Base = fallback_class("Base", nil, { fallback_provides = { "compare" } })
  core.finalise(Base)
  local Derived = core.class("Derived", Base, { implements = { I } })
  core.finalise(Derived)
  self:assert_true(core.implements(Derived, I))
  local Own = core.class("Own", Base, { implements = { I } })
  Own.__index = function() return 1 end
  core.finalise(Own)
end

function T:test_subclass_may_declare_names_behind_inherited_fallback()
  local I = core.interface("I", { "extra" })
  local Base = fallback_class("Base")
  core.finalise(Base)
  local Derived = core.class("Derived", Base, { implements = { I }, fallback_provides = { "extra" } })
  core.finalise(Derived)
end

function T:test_fallback_provides_must_be_a_list_of_names()
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: assign-type-mismatch
    core.class("A", nil, { fallback_provides = { 1 } })
  end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

return T
