local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("AllocateTest")

local function point_class()
  local Point = core.class("Point")
  function Point:init(x) self.x = x; self.initialised = true end
  function Point:norm() return self.x or 0 end
  core.finalise(Point)
  return Point
end

function T:test_allocate_does_not_call_init()
  local Point = point_class()
  local p = core.allocate(Point)
  self:assert_equal(nil, p.initialised)
  self:assert_equal(nil, next(p))
end

function T:test_allocate_gives_a_real_instance()
  local Point = point_class()
  local p = core.allocate(Point)
  self:assert_true(core.is_instance_of(p, Point))
  self:assert_true(core.class_of(p) == Point)
  p.x = 3
  self:assert_equal(3, p:norm())
end

function T:test_allocate_inherits_members_and_metamethods()
  local Base = core.class("Base")
  function Base:hello() return "hello" end
  function Base:__tostring() return "base-object" end
  core.finalise(Base)
  local Derived = core.class("Derived", Base)
  core.finalise(Derived)
  local d = core.allocate(Derived)
  self:assert_equal("hello", d:hello())
  self:assert_equal("base-object", tostring(d))
  self:assert_true(core.is_instance_of(d, Base))
end

function T:test_allocate_refuses_a_non_class()
  for _, value in ipairs({ 1, "A", {}, core.interface("I", { "m" }), core.trait("Tr", {}) }) do
    local err = self:assert_error(function() return core.allocate(value) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
end

function T:test_allocate_refuses_a_class_not_finalised()
  local A = core.class("A")
  local err = self:assert_error(function() return core.allocate(A) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_true(err.message:find("A", 1, true) ~= nil)
end

function T:test_allocate_refuses_a_value_class()
  local V = core.value_class("V")
  core.finalise(V)
  local err = self:assert_error(function() return core.allocate(V) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
  self:assert_true(err.message:find("V", 1, true) ~= nil)
end

function T:test_weak_table_modes()
  local function collects(mode, as_key)
    local t = core.weak_table(mode)
    do
      local obj = {}
      if as_key then t[obj] = true else t[1] = obj end
    end
    collectgarbage(); collectgarbage()
    return next(t) == nil
  end
  self:assert_true(collects(nil, true))
  self:assert_true(collects("k", true))
  self:assert_true(collects("v", false))
  self:assert_true(collects("kv", true))
  self:assert_true(not collects("k", false))
  self:assert_true(not collects("v", true))
end

function T:test_weak_table_refuses_an_unknown_mode()
  local mode = "x" ---@type any
  local err = self:assert_error(function() return core.weak_table(mode) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_weak_table_is_a_clean_table()
  local t = core.weak_table()
  t.a = 1
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  self:assert_equal(1, n)
end

return T
