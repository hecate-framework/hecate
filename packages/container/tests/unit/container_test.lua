---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field  -- the tests pass invalid arguments on purpose
-- Binding, lifetimes, resolution, construction, disposal, overrides and errors (container.md).
local test = require("harness.test")
local core = require("hecate.core")
local container = require("hecate.container")
local T = test.Case("ContainerTest")

local function raises(case, class, fn)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, class), tostring(err))
  return err
end

--- A class whose instances record their dependencies and count constructions.
local function service_class(name)
  local class = core.class(name)
  class.count = 0
  function class:init(...)
    class.count = class.count + 1
    self.dependencies = { ... }
  end
  return core.finalise(class)
end

local function ready(setup)
  local c = container.Container()
  setup(c)
  return c:validate()
end

-- Binding arguments ------------------------------------------------------------------------------------------------

function T:test_bind_is_chainable()
  local Clock = service_class("Clock")
  local c = container.Container()
  self:assert_true(c:bind("clock", Clock, { lifetime = "transient" }) == c)
  c:validate()
  self:assert_false(c:resolve("clock") == c:resolve("clock"))
  self:assert_equal(2, Clock.count)
end

function T:test_bind_without_a_lifetime_raises_an_argument_error_naming_the_lifetimes()
  local c = container.Container()
  for _, fn in ipairs({
    function() c:bind("a", function() return {} end) end,
    function() c:bind("a", function() return {} end, {}) end,
    function() c:bind("a", function() return {} end, { requires = { "b" } }) end,
  }) do
    local err = raises(self, core.ArgumentError, fn)
    for _, name in ipairs({ "lifetime", "singleton", "scoped", "transient" }) do
      self:assert_true(tostring(err.message):find(name, 1, true) ~= nil, name)
    end
  end
  -- Nothing was bound by the refused calls.
  c:bind("a", function() return {} end, { lifetime = "singleton" })
end

function T:test_override_with_options_without_a_lifetime_raises_an_argument_error()
  local c = container.Container():bind("a", function() return {} end, { lifetime = "singleton" })
  raises(self, core.ArgumentError, function() c:override("a", function() return {} end, {}) end)
  raises(self, core.ArgumentError, function() c:override("a", function() return {} end, { requires = { "b" } }) end)
end

function T:test_override_without_options_keeps_the_lifetime_and_requires()
  local c = container.Container()
  c:bind("dep", function() return {} end, { lifetime = "singleton" })
  c:bind("a", function(dep) return { dep = dep, id = "real" } end, { lifetime = "scoped", requires = { "dep" } })
  c:override("a", function(dep) return { dep = dep, id = "fake" } end)
  c:validate()
  local scope = c:open_scope()
  local first = scope:resolve("a")
  self:assert_equal("fake", first.id)
  self:assert_true(first.dep == c:resolve("dep"))
  self:assert_true(first == scope:resolve("a"))
  scope:close()
end

function T:test_bind_refuses_wrong_arguments()
  local c = container.Container()
  local Open = core.class("Open")
  local bad = {
    function() c:bind("", function() end) end,
    function() c:bind(42, function() end) end,
    function() c:bind("a", 42) end,
    function() c:bind("a", Open) end,
    function() c:bind("a", function() end, { lifetime = "forever" }) end,
    function() c:bind("a", function() end, { lifetime = 3 }) end,
    function() c:bind("a", function() end, { lifetime = "transient", requires = "b" }) end,
    function() c:bind("a", function() end, { lifetime = "transient", requires = { "b", 3 } }) end,
    function() c:bind("a", function() end, { lifetime = "transient", requires = { x = "b" } }) end,
    function() c:bind("a", function() end, { requirements = {} }) end,
    function() c:bind("a", function() end, 7) end,
    function() c:resolve({}) end,
  }
  for i, fn in ipairs(bad) do raises(self, core.ArgumentError, fn) end
end

function T:test_a_lifetime_is_given_as_a_member_or_its_name()
  local Thing = service_class("Thing")
  local c = ready(function(c)
    c:bind("a", Thing, { lifetime = container.Lifetime.singleton })
    c:bind("b", Thing, { lifetime = "singleton" })
  end)
  self:assert_true(c:resolve("a") == c:resolve("a"))
  self:assert_true(c:resolve("b") == c:resolve("b"))
end

function T:test_binding_a_bound_key_raises_duplicate_binding_error()
  local c = container.Container():bind("a", function() return {} end, { lifetime = "transient" })
  local err = raises(self, container.DuplicateBindingError, function() c:bind("a", function() return {} end, { lifetime = "transient" }) end)
  self:assert_equal("a", err.context.key)
  self:assert_equal("hecate.container.DuplicateBindingError", err.code)
end

function T:test_every_error_extends_the_configuration_error()
  for _, name in ipairs({ "ContainerError", "DuplicateBindingError", "MissingBindingError", "CycleError",
    "LifetimeError", "GraphError", "ConstructionError" }) do
    self:assert_true(core.is_instance_of(container[name]("x"), core.ConfigurationError), name)
  end
end

-- Constructor injection ---------------------------------------------------------------------------------------------

function T:test_dependencies_are_passed_in_the_order_of_requires()
  local A, B = service_class("A"), service_class("B")
  local User = service_class("User")
  local c = ready(function(c)
    c:bind("a", A, { lifetime = "singleton" })
    c:bind("b", B, { lifetime = "transient" })
    c:bind("user", User, { lifetime = "transient", requires = { "b", "a" } })
  end)
  local user = c:resolve("user")
  self:assert_true(core.is_instance_of(user.dependencies[1], B))
  self:assert_true(user.dependencies[2] == c:resolve("a"))
end

function T:test_a_factory_receives_the_same_arguments()
  local received
  local c = ready(function(c)
    c:bind("clock", function() return { now = 1 } end, { lifetime = "singleton" })
    c:bind("users", function(clock, extra) received = { clock, extra }; return { clock = clock } end,
      { lifetime = "transient", requires = { "clock" } })
  end)
  local users = c:resolve("users")
  self:assert_true(users.clock == c:resolve("clock"))
  self:assert_nil(received[2])
end

function T:test_an_interface_is_a_key_like_a_name()
  local Repo = core.interface("Repo", { "find" })
  local Pg = core.class("Pg", nil, { implements = { Repo } })
  function Pg:find() return "row" end
  core.finalise(Pg)
  local c = ready(function(c)
    c:bind(Repo, Pg, { lifetime = "singleton" })
    c:bind("consumer", function(repo) return { repo = repo } end, { lifetime = "transient", requires = { Repo } })
  end)
  self:assert_equal("row", c:resolve("consumer").repo:find())
  self:assert_true(c:resolve(Repo) == c:resolve(Repo))
end

function T:test_a_factory_product_is_checked_against_an_interface_key_at_first_construction()
  local Repo = core.interface("Repo", { "find" })
  local c = ready(function(c) c:bind(Repo, function() return {} end, { lifetime = "transient" }) end)
  raises(self, core.ConformanceError, function() c:resolve(Repo) end)
end

function T:test_a_constructor_returning_nil_is_a_construction_error()
  local c = ready(function(c) c:bind("a", function() end, { lifetime = "transient" }) end)
  raises(self, container.ConstructionError, function() c:resolve("a") end)
end

-- Lifetimes ----------------------------------------------------------------------------------------------------------

function T:test_a_singleton_is_shared_by_the_container_and_every_scope()
  local S = service_class("S")
  local c = ready(function(c) c:bind("s", S, { lifetime = "singleton" }) end)
  local one, two = c:open_scope(), c:open_scope()
  self:assert_true(c:resolve("s") == one:resolve("s"))
  self:assert_true(one:resolve("s") == two:resolve("s"))
  self:assert_equal(1, S.count)
end

function T:test_a_scoped_service_is_shared_inside_a_scope_and_distinct_across_scopes()
  local R = service_class("R")
  local c = ready(function(c)
    c:bind("r", R, { lifetime = "scoped" })
    c:bind("a", function(r) return { r = r } end, { lifetime = "transient", requires = { "r" } })
    c:bind("b", function(r) return { r = r } end, { lifetime = "transient", requires = { "r" } })
  end)
  local one, two = c:open_scope(), c:open_scope()
  self:assert_true(one:resolve("r") == one:resolve("r"))
  self:assert_true(one:resolve("a").r == one:resolve("b").r, "consumers inside a scope share the instance")
  self:assert_false(one:resolve("r") == two:resolve("r"))
  self:assert_equal(2, R.count)
end

function T:test_the_scope_is_a_plain_value_so_every_holder_sees_the_same_instances()
  -- The kernel hands one scope to every computation forked by a request; sharing across `fork` is sharing the value.
  local R = service_class("R")
  local c = ready(function(c) c:bind("r", R, { lifetime = "scoped" }) end)
  local scope = c:open_scope()
  local holders = {}
  for i = 1, 3 do holders[i] = function() return scope:resolve("r") end end
  self:assert_true(holders[1]() == holders[2]() and holders[2]() == holders[3]())
end

function T:test_a_transient_is_never_cached_even_inside_a_scope()
  local Tr = service_class("Tr")
  local c = ready(function(c) c:bind("t", Tr, { lifetime = "transient" }) end)
  local scope = c:open_scope()
  self:assert_false(scope:resolve("t") == scope:resolve("t"))
end

function T:test_resolving_a_scoped_service_from_the_root_raises_a_lifetime_error_before_building_anything()
  local Before = service_class("Before")
  local c = ready(function(c)
    c:bind("before", Before, { lifetime = "transient" })
    c:bind("r", service_class("R"), { lifetime = "scoped" })
    c:bind("t", function() end, { lifetime = "transient", requires = { "before", "r" } })
  end)
  local err = raises(self, container.LifetimeError, function() c:resolve("r") end)
  self:assert_equal("r", err.context.key)
  err = raises(self, container.LifetimeError, function() c:resolve("t") end)
  self:assert_equal("t", err.context.key)
  self:assert_equal("r", err.context.dependency)
  self:assert_equal("t,r", table.concat(err.context.path, ","))
  self:assert_equal(0, Before.count, "no dependency was constructed")
end

function T:test_a_root_resolvable_transient_over_singletons_resolves_from_the_root()
  local c = ready(function(c)
    c:bind("s", function() return {} end, { lifetime = "singleton" })
    c:bind("t", function(s) return { s = s } end, { lifetime = "transient", requires = { "s" } })
  end)
  self:assert_true(c:resolve("t").s == c:resolve("s"))
end

function T:test_an_unbound_key_raises_missing_binding_error()
  local c = ready(function() end)
  local err = raises(self, container.MissingBindingError, function() c:resolve("ghost") end)
  self:assert_equal("ghost", err.context.key)
  raises(self, container.MissingBindingError, function() c:open_scope():resolve("ghost") end)
end

-- Construction ---------------------------------------------------------------------------------------------------------

function T:test_a_constructor_error_is_wrapped_with_key_path_and_cause()
  local failure = core.Error("boom")
  local c = ready(function(c)
    c:bind("top", function() return {} end, { lifetime = "transient", requires = { "bad" } })
    c:bind("bad", function() error(failure) end, { lifetime = "transient" })
  end)
  local err = raises(self, container.ConstructionError, function() c:resolve("top") end)
  self:assert_equal("bad", err.context.key)
  self:assert_equal("top,bad", table.concat(err.context.path, ","))
  self:assert_true(err.cause == failure)
end

function T:test_a_string_error_is_wrapped_too()
  local c = ready(function(c) c:bind("bad", function() error("plain", 0) end, { lifetime = "transient" }) end)
  local err = raises(self, container.ConstructionError, function() c:resolve("bad") end)
  self:assert_equal("plain", err.cause)
end

function T:test_cancellation_and_deadline_errors_are_not_wrapped()
  for _, class in ipairs({ core.CancellationError, core.DeadlineExceededError }) do
    local original = class("stop")
    local c = ready(function(c) c:bind("a", function() error(original) end, { lifetime = "transient" }) end)
    local err = self:assert_error(function() c:resolve("a") end)
    self:assert_true(err == original)
  end
end

function T:test_a_failed_construction_caches_nothing()
  local attempts = 0
  local c = ready(function(c)
    c:bind("flaky", function()
      attempts = attempts + 1
      if attempts == 1 then error("first time") end
      return { attempts = attempts }
    end, { lifetime = "singleton" })
  end)
  self:assert_error(function() c:resolve("flaky") end)
  self:assert_equal(2, c:resolve("flaky").attempts)
  self:assert_equal(2, c:resolve("flaky").attempts)
end

function T:test_a_reentrant_resolution_raises_cycle_error()
  local c
  c = ready(function(self_c)
    self_c:bind("a", function() return c:resolve("a") end, { lifetime = "singleton" })
  end)
  local err = raises(self, container.ConstructionError, function() c:resolve("a") end)
  self:assert_true(core.is_instance_of(err.cause, container.CycleError))
  self:assert_equal("a,a", table.concat(err.cause.context.path, ","))
  -- and the guard is released: the container is usable afterwards
  raises(self, container.ConstructionError, function() c:resolve("a") end)
end

-- Disposal --------------------------------------------------------------------------------------------------------------

local function closing_class(name, log, fail)
  local class = core.class(name)
  function class:init() self.name = name end
  function class:__close()
    log[#log + 1] = name
    if fail then error(core.Error(name .. " failed")) end
  end
  return core.finalise(class)
end

function T:test_a_scope_closes_its_scoped_services_in_reverse_order_of_creation()
  local log = {}
  local First, Second, Single = closing_class("First", log), closing_class("Second", log), closing_class("Single", log)
  local c = ready(function(c)
    c:bind("first", First, { lifetime = "scoped" })
    c:bind("second", Second, { lifetime = "scoped", requires = { "first" } })
    c:bind("single", Single, { lifetime = "singleton" })
    c:bind("plain", function() return {} end, { lifetime = "scoped" })
  end)
  local scope = c:open_scope()
  scope:resolve("plain")
  scope:resolve("second")
  scope:resolve("single")
  scope:close()
  self:assert_equal("Second,First", table.concat(log, ","))
  scope:close()
  self:assert_equal(2, #log, "closing is idempotent")
  c:close()
  self:assert_equal("Second,First,Single", table.concat(log, ","))
end

function T:test_the_container_closes_its_singletons_in_reverse_order()
  local log = {}
  local A, B = closing_class("A", log), closing_class("B", log)
  local c = ready(function(c)
    c:bind("a", A, { lifetime = "singleton" })
    c:bind("b", B, { lifetime = "singleton", requires = { "a" } })
  end)
  c:resolve("b")
  c:close()
  self:assert_equal("B,A", table.concat(log, ","))
  c:close()
  self:assert_equal(2, #log)
end

function T:test_a_closable_transient_is_tracked_by_its_scope_and_closed_in_reverse_order_with_scoped_services()
  local log = {}
  local S1, T1, S2, T2 = closing_class("S1", log), closing_class("T1", log), closing_class("S2", log),
    closing_class("T2", log)
  local c = ready(function(c)
    c:bind("s1", S1, { lifetime = "scoped" })
    c:bind("t1", T1, { lifetime = "transient" })
    c:bind("s2", S2, { lifetime = "scoped" })
    c:bind("t2", function() return T2() end, { lifetime = "transient" })
  end)
  local scope = c:open_scope()
  local first = scope:resolve("t1")
  scope:resolve("s1")
  scope:resolve("t1")
  scope:resolve("s2")
  scope:resolve("t2")
  self:assert_false(first == scope:resolve("t1"))
  scope:close()
  -- created: T1, S1, T1, S2, T2, then the T1 of the comparison above
  self:assert_equal("T1,T2,S2,T1,S1,T1", table.concat(log, ","), "reverse order of creation")
end

function T:test_a_transient_without_close_is_never_tracked()
  local c = ready(function(c)
    c:bind("plain", function() return {} end, { lifetime = "transient" })
    c:bind("plain_class", service_class("Plain"), { lifetime = "transient" })
  end)
  local scope = c:open_scope()
  for _ = 1, 50 do
    scope:resolve("plain")
    scope:resolve("plain_class")
  end
  self:assert_equal(0, #scope._owned)
  self:assert_equal(0, #c._owned)
  local instance = scope:resolve("plain")
  raises(self, container.ContainerError, function() scope:release(instance) end)
end

function T:test_a_transient_dependency_of_a_transient_in_a_scope_is_tracked()
  local log = {}
  local Inner, Outer = closing_class("Inner", log), closing_class("Outer", log)
  local c = ready(function(c)
    c:bind("inner", Inner, { lifetime = "transient" })
    c:bind("outer", Outer, { lifetime = "transient", requires = { "inner" } })
    c:bind("plain", function(inner) return { inner = inner } end, { lifetime = "transient", requires = { "inner" } })
  end)
  local scope = c:open_scope()
  scope:resolve("outer")
  scope:resolve("plain")
  scope:close()
  -- created: Inner, Outer, Inner (for "plain"); closed in reverse
  self:assert_equal("Inner,Outer,Inner", table.concat(log, ","))
end

function T:test_a_closable_transient_of_a_singleton_is_owned_by_the_container()
  local log = {}
  local Dep, Single = closing_class("Dep", log), closing_class("Single", log)
  local c = ready(function(c)
    c:bind("dep", Dep, { lifetime = "transient" })
    c:bind("single", Single, { lifetime = "singleton", requires = { "dep" } })
  end)
  local scope = c:open_scope()
  scope:resolve("single")
  scope:close()
  self:assert_equal(0, #log, "the scope does not own it")
  c:close()
  self:assert_equal("Single,Dep", table.concat(log, ","))
end

function T:test_a_singleton_built_from_the_root_owns_its_closable_transient_without_error()
  local log = {}
  local Dep = closing_class("Dep", log)
  local c = ready(function(c)
    c:bind("dep", function() return Dep() end, { lifetime = "transient" })
    c:bind("single", function(dep) return { dep = dep } end, { lifetime = "singleton", requires = { "dep" } })
  end)
  c:resolve("single")
  c:close()
  self:assert_equal("Dep", table.concat(log, ","))
end

function T:test_the_root_refuses_a_closable_transient_class()
  local log = {}
  local Tr = closing_class("Tr", log)
  local c = ready(function(c)
    c:bind("t", Tr, { lifetime = "transient" })
    c:bind("user", function(t) return { t = t } end, { lifetime = "transient", requires = { "t" } })
  end)
  local err = raises(self, container.LifetimeError, function() c:resolve("t") end)
  self:assert_equal("t", err.context.key)
  self:assert_true(tostring(err.message):find("open_scope", 1, true) ~= nil)
  local nested = raises(self, container.LifetimeError, function() c:resolve("user") end)
  self:assert_equal("user", nested.context.key)
  self:assert_equal("t", nested.context.dependency)
  self:assert_equal(0, #log, "a class is refused before it is built")
  self:assert_equal(0, Tr.count or 0)
end

function T:test_the_root_closes_a_closable_factory_product_and_raises()
  local log = {}
  local A, B = closing_class("A", log), closing_class("B", log)
  local c = ready(function(c)
    c:bind("a", function() return A() end, { lifetime = "transient" })
    c:bind("b", function(a) return B() end, { lifetime = "transient", requires = { "a" } })
  end)
  raises(self, container.LifetimeError, function() c:resolve("a") end)
  self:assert_equal("A", table.concat(log, ","))
  self:assert_equal(0, #c._owned)
  log[1] = nil
  local err = raises(self, container.LifetimeError, function() c:resolve("b") end)
  self:assert_equal("a", err.context.dependency)
  self:assert_equal("A", table.concat(log, ","))
end

function T:test_the_root_closes_every_product_built_in_the_call_in_reverse_order()
  local log = {}
  local A, B = closing_class("A", log), closing_class("B", log)
  local c = ready(function(c)
    c:bind("a", function() return A() end, { lifetime = "transient" })
    c:bind("b", B, { lifetime = "transient" })
    c:bind("top", function() return {} end, { lifetime = "transient", requires = { "a", "b" } })
  end)
  -- the first product is refused at once: nothing else is built
  raises(self, container.LifetimeError, function() c:resolve("top") end)
  self:assert_equal("A", table.concat(log, ","))
end

function T:test_release_closes_once_and_stops_tracking()
  local log = {}
  local Tr, Scoped = closing_class("Tr", log), closing_class("Sc", log)
  local c = ready(function(c)
    c:bind("t", Tr, { lifetime = "transient" })
    c:bind("s", Scoped, { lifetime = "scoped" })
  end)
  local scope = c:open_scope()
  local instance = scope:resolve("t")
  local kept = scope:resolve("t")
  scope:resolve("s")
  self:assert_equal(nil, scope:release(instance))
  self:assert_equal("Tr", table.concat(log, ","))
  raises(self, container.ContainerError, function() scope:release(instance) end)
  scope:close()
  self:assert_equal("Tr,Sc,Tr", table.concat(log, ","), "no double close; the other transient closes with the scope")
  self:assert_true(kept ~= nil)
end

function T:test_release_refuses_what_the_scope_does_not_track()
  local log = {}
  local Tr, Scoped, Dep, Single = closing_class("Tr", log), closing_class("Sc", log), closing_class("Dep", log),
    closing_class("Single", log)
  local c = ready(function(c)
    c:bind("t", Tr, { lifetime = "transient" })
    c:bind("s", Scoped, { lifetime = "scoped" })
    c:bind("dep", Dep, { lifetime = "transient" })
    c:bind("single", Single, { lifetime = "singleton", requires = { "dep" } })
  end)
  local one, two = c:open_scope(), c:open_scope()
  local instance = one:resolve("t")
  raises(self, container.ContainerError, function() two:release(instance) end)
  raises(self, container.ContainerError, function() one:release(one:resolve("s")) end)
  raises(self, container.ContainerError, function() one:release({}) end)
  raises(self, container.ContainerError, function() one:release(one:resolve("single")) end)
  for _, bad in ipairs({ 1, "x", true }) do
    raises(self, core.ArgumentError, function() one:release(bad) end)
  end
  raises(self, core.ArgumentError, function() one:release(nil) end)
  self:assert_equal(0, #log)
end

function T:test_a_close_error_in_release_propagates_as_it_is()
  local log = {}
  local Bad = closing_class("Bad", log, true)
  local c = ready(function(c) c:bind("t", Bad, { lifetime = "transient" }) end)
  local scope = c:open_scope()
  local instance = scope:resolve("t")
  local err = raises(self, core.Error, function() scope:release(instance) end)
  self:assert_equal("Bad failed", err.message)
  scope:close()
  self:assert_equal("Bad", table.concat(log, ","), "not closed again by the scope")
end

function T:test_close_errors_of_transients_aggregate_with_the_others()
  local log = {}
  local Bad1, Bad2 = closing_class("Bad1", log, true), closing_class("Bad2", log, true)
  local c = ready(function(c)
    c:bind("one", Bad1, { lifetime = "transient" })
    c:bind("two", Bad2, { lifetime = "scoped" })
  end)
  local scope = c:open_scope()
  scope:resolve("one")
  scope:resolve("two")
  local err = self:assert_error(function() scope:close() end)
  self:assert_equal("Bad2 failed", err.message)
  self:assert_equal(1, #err.context.suppressed)
  self:assert_equal("Bad2,Bad1", table.concat(log, ","))
end

function T:test_every_close_is_attempted_and_the_first_error_carries_the_others()
  local log = {}
  local A, B, C = closing_class("A", log, true), closing_class("B", log, true), closing_class("C", log, false)
  local c = ready(function(c)
    c:bind("a", A, { lifetime = "scoped" })
    c:bind("b", B, { lifetime = "scoped" })
    c:bind("c", C, { lifetime = "scoped" })
  end)
  local scope = c:open_scope()
  scope:resolve("a"); scope:resolve("b"); scope:resolve("c")
  local err = self:assert_error(function() scope:close() end)
  self:assert_equal("C,B,A", table.concat(log, ","), "all were attempted")
  self:assert_equal("B failed", err.message)
  self:assert_equal(1, #err.context.suppressed)
  self:assert_equal("A failed", err.context.suppressed[1].message)
end

function T:test_a_close_that_raises_a_non_error_is_wrapped()
  local class = core.class("Raw")
  function class:__close() error("raw", 0) end
  core.finalise(class)
  local c = ready(function(c) c:bind("r", class, { lifetime = "singleton" }) end)
  c:resolve("r")
  local err = raises(self, container.ContainerError, function() c:close() end)
  self:assert_equal("raw", err.cause)
end

function T:test_scope_and_container_support_to_be_closed_variables()
  local log = {}
  local R, S = closing_class("R", log), closing_class("S", log)
  local c = ready(function(c)
    c:bind("r", R, { lifetime = "scoped" })
    c:bind("s", S, { lifetime = "singleton" })
  end)
  do
    local scope <close> = c:open_scope()
    scope:resolve("r")
    scope:resolve("s")
  end
  self:assert_equal("R", table.concat(log, ","))
  do
    local owner <close> = c
  end
  self:assert_equal("R,S", table.concat(log, ","))
end

function T:test_a_closed_scope_or_container_refuses_to_resolve()
  local c = ready(function(c) c:bind("a", function() return {} end, { lifetime = "transient" }) end)
  local scope = c:open_scope()
  scope:close()
  raises(self, container.ContainerError, function() scope:resolve("a") end)
  local other = c:open_scope()
  c:close()
  raises(self, container.ContainerError, function() c:resolve("a") end)
  raises(self, container.ContainerError, function() other:resolve("a") end)
  raises(self, container.ContainerError, function() c:open_scope() end)
  raises(self, container.ContainerError, function() c:bind("b", function() return {} end, { lifetime = "transient" }) end)
end

-- Overrides ----------------------------------------------------------------------------------------------------------------

function T:test_override_of_an_unbound_key_raises_missing_binding_error()
  local c = container.Container()
  local err = raises(self, container.MissingBindingError, function() c:override("typo", function() return {} end) end)
  self:assert_equal("typo", err.context.key)
  raises(self, container.MissingBindingError, function() c:override_with_instance("typo", {}) end)
end

function T:test_override_keeps_lifetime_and_requires_when_options_are_omitted()
  local c = container.Container()
  c:bind("dep", function() return { id = "dep" } end, { lifetime = "singleton" })
  c:bind("a", function(dep) return { dep = dep, id = "real" } end, { lifetime = "singleton", requires = { "dep" } })
  c:override("a", function(dep) return { dep = dep, id = "fake" } end)
  c:validate()
  local a = c:resolve("a")
  self:assert_equal("fake", a.id)
  self:assert_true(a.dep == c:resolve("dep"))
  self:assert_true(a == c:resolve("a"), "still a singleton")
end

function T:test_override_with_options_replaces_both()
  local c = container.Container()
  c:bind("dep", function() return {} end, { lifetime = "transient" })
  c:bind("a", function() return { id = "real" } end, { lifetime = "singleton", requires = { "dep" } })
  c:override("a", function(...) return { n = select("#", ...) } end, { lifetime = "transient" })
  c:validate()
  self:assert_equal(0, c:resolve("a").n)
  self:assert_false(c:resolve("a") == c:resolve("a"))
end

function T:test_override_keeps_the_position_in_the_registration_order()
  local c = container.Container():bind("a", function() return {} end, { lifetime = "transient", requires = { "x" } })
  c:bind("b", function() return {} end, { lifetime = "transient", requires = { "y" } })
  c:override("a", function() return {} end, { lifetime = "transient", requires = { "z" } })
  local err = self:assert_error(function() c:validate() end)
  self:assert_equal("z", err.context.problems[1].context.key)
  self:assert_equal("y", err.context.problems[2].context.key)
end

function T:test_override_with_instance_injects_a_fake_as_a_singleton()
  local fake = { fake = true }
  local c = container.Container()
  c:bind("clock", function() return {} end, { lifetime = "scoped", requires = { "ghost" } })
  c:override_with_instance("clock", fake)
  c:bind("user", function(clock) return { clock = clock } end, { lifetime = "transient", requires = { "clock" } })
  c:validate()
  self:assert_true(c:resolve("user").clock == fake)
  raises(self, core.ArgumentError, function() container.Container():bind("a", function() return {} end, { lifetime = "transient" }):override_with_instance("a", nil) end)
end

function T:test_override_with_instance_checks_an_interface_key_at_the_call()
  local Repo = core.interface("Repo", { "find" })
  local Pg = core.class("Pg", nil, { implements = { Repo } })
  function Pg:find() return "row" end
  core.finalise(Pg)
  local c = container.Container():bind(Repo, Pg, { lifetime = "singleton" })
  raises(self, core.ConformanceError, function() c:override_with_instance(Repo, {}) end)
  local Other = core.finalise(core.class("Other"))
  raises(self, core.ConformanceError, function() c:override_with_instance(Repo, Other()) end)
  c:validate()
  self:assert_equal("row", c:resolve(Repo):find(), "the binding is unchanged after the failure")
end

function T:test_override_with_instance_accepts_a_conformant_fake()
  local Repo = core.interface("Repo", { "find" })
  local Fake = core.class("FakeRepo", nil, { implements = { Repo } })
  function Fake:find() return "fake" end
  core.finalise(Fake)
  local fake = Fake()
  local c = container.Container():bind(Repo, function() return fake end, { lifetime = "transient" })
  c:override_with_instance(Repo, fake):validate()
  self:assert_true(c:resolve(Repo) == fake)
end

function T:test_override_with_instance_checks_nothing_for_a_name_key()
  local c = container.Container():bind("a", function() return {} end, { lifetime = "transient" })
  c:override_with_instance("a", 42):validate()
  self:assert_equal(42, c:resolve("a"))
end

function T:test_override_after_validate_raises_container_error()
  local c = container.Container():bind("a", function() return {} end, { lifetime = "transient" }):validate()
  raises(self, container.ContainerError, function() c:override("a", function() return {} end) end)
  raises(self, container.ContainerError, function() c:override_with_instance("a", {}) end)
end

return T
