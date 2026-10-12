local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("ValueClassTest")

local function money_class()
  local Money = core.value_class("Money")
  function Money:init(amount, currency) self.amount, self.currency = amount, currency end
  function Money:plus(other) return Money(self.amount + other.amount, self.currency) end
  core.finalise(Money)
  return Money
end

function T:test_fields_are_readable_after_construction()
  local m = money_class()(5, "EUR")
  self:assert_equal(5, m.amount)
  self:assert_equal("EUR", m.currency)
end

function T:test_methods_work()
  local Money = money_class()
  self:assert_equal(8, Money(5, "EUR"):plus(Money(3, "EUR")).amount)
end

function T:test_writes_to_existing_fields_raise()
  local m = money_class()(5, "EUR")
  local err = self:assert_error(function() m.amount = 6 end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("amount", 1, true) ~= nil)
  self:assert_true(err.message:find("Money", 1, true) ~= nil)
  self:assert_equal(5, m.amount)
end

function T:test_writes_of_new_fields_raise()
  local m = money_class()(5, "EUR")
  self:assert_error(function() m.extra = 1 end)
  self:assert_nil(m.extra)
end

function T:test_instance_table_holds_no_fields()
  -- reads go through a table __index, never a function (invariant: no function on the read path)
  local m = money_class()(5, "EUR")
  self:assert_nil(rawget(m, "amount"))
  self:assert_equal("table", type(getmetatable(m).__index))
end

function T:test_structural_equality()
  local Money = money_class()
  self:assert_true(Money(5, "EUR") == Money(5, "EUR"))
  self:assert_false(Money(5, "EUR") == Money(6, "EUR"))
  self:assert_false(Money(5, "EUR") == Money(5, "USD"))
  self:assert_true(Money(5, "EUR") ~= Money(5, "USD"))
end

function T:test_equality_across_classes_is_false()
  local A = core.value_class("A")
  function A:init(v) self.v = v end
  core.finalise(A)
  local B = core.value_class("B")
  function B:init(v) self.v = v end
  core.finalise(B)
  self:assert_false(A(1) == B(1))
end

function T:test_nested_value_objects_compare_structurally()
  local Money = money_class()
  local Line = core.value_class("Line")
  function Line:init(price) self.price = price end
  core.finalise(Line)
  self:assert_true(Line(Money(1, "EUR")) == Line(Money(1, "EUR")))
  self:assert_false(Line(Money(1, "EUR")) == Line(Money(2, "EUR")))
end

function T:test_custom_eq_wins_over_structural()
  local A = core.value_class("A")
  function A:init(v) self.v = v end
  function A.__eq() return true end
  core.finalise(A)
  self:assert_true(A(1) == A(2))
end

function T:test_pairs_iterates_fields()
  local m = money_class()(5, "EUR")
  local seen = {}
  for k, v in pairs(m) do seen[k] = v end
  self:assert_equal(5, seen.amount)
  self:assert_equal("EUR", seen.currency)
end

function T:test_introspection_works_on_value_objects()
  local Money = money_class()
  local m = Money(1, "EUR")
  self:assert_true(core.class_of(m) == Money)
  self:assert_true(core.is_instance_of(m, Money))
  self:assert_equal("Money", core.name(m))
end

function T:test_value_subclass_is_frozen_too()
  local Base = core.value_class("Base")
  function Base:init(a) self.a = a end
  core.finalise(Base)
  local Derived = core.value_class("Derived", Base)
  function Derived:init(a, b)
    core.superclass(Derived).init(self, a)
    self.b = b
  end
  core.finalise(Derived)
  local d = Derived(1, 2)
  self:assert_equal(2, d.b)
  self:assert_error(function() d.a = 5 end)
  self:assert_true(Derived(1, 2) == d)
  self:assert_true(core.is_instance_of(d, Base))
end

function T:test_plain_subclass_of_value_class_stays_frozen()
  local Base = core.value_class("Base")
  function Base:init(a) self.a = a end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  local d = Derived(1)
  self:assert_error(function() d.a = 2 end)
end

function T:test_value_class_cannot_extend_a_plain_class()
  local Plain = core.class("Plain")
  core.finalise(Plain)
  local err = self:assert_error(function() core.value_class("V", Plain) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_inherited_metamethods_are_available()
  local V = core.value_class("V")
  function V:init(n) self.n = n end
  function V:__tostring() return "V" .. self.n end
  function V.__lt(a, b) return a.n < b.n end
  function V:__close() end
  core.finalise(V)
  self:assert_equal("V3", tostring(V(3)))
  self:assert_true(V(1) < V(2))
  do local v <close> = V(1) end
end

function T:test_traits_and_interfaces_apply()
  local I = core.interface("I", { "show" })
  local V = core.value_class("V", nil, { implements = { I } })
  function V:show() end
  core.finalise(V)
  self:assert_true(core.implements(V(), I))
end

return T
