---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Boot validation (container.md, "Boot validation"): every kind of problem, aggregation, order, freezing.
local test = require("harness.test")
local core = require("hecate.core")
local container = require("hecate.container")
local T = test.Case("ContainerValidateTest")

local Thing = core.finalise(core.class("Thing"))
local function thing() return Thing() end

local function problems_of(c)
  local err = T:assert_error(function() c:validate() end)
  T:assert_true(core.is_instance_of(err, container.GraphError), tostring(err))
  return err.context.problems, err
end

function T:test_a_valid_graph_validates_and_returns_the_container()
  local c = container.Container():bind("a", thing, { lifetime = "transient" }):bind("b", thing, { lifetime = "transient", requires = { "a" } })
  self:assert_true(c:validate() == c)
  self:assert_true(c:validate() == c, "validating again is allowed")
end

function T:test_a_missing_binding_names_the_key_and_the_path()
  local c = container.Container():bind("a", thing, { lifetime = "transient", requires = { "ghost" } })
  local problems, err = problems_of(c)
  self:assert_equal(1, #problems)
  self:assert_true(core.is_instance_of(problems[1], container.MissingBindingError))
  self:assert_equal("ghost", problems[1].context.key)
  self:assert_equal("a,ghost", table.concat(problems[1].context.path, ","))
  self:assert_true(core.is_instance_of(err, container.ContainerError))
end

function T:test_a_binding_that_requires_itself_is_a_cycle_of_length_one()
  local problems = problems_of(container.Container():bind("a", thing, { lifetime = "transient", requires = { "a" } }))
  self:assert_true(core.is_instance_of(problems[1], container.CycleError))
  self:assert_equal("a,a", table.concat(problems[1].context.path, ","))
end

function T:test_a_cycle_of_length_two()
  local c = container.Container():bind("a", thing, { lifetime = "transient", requires = { "b" } }):bind("b", thing, { lifetime = "transient", requires = { "a" } })
  local problems = problems_of(c)
  self:assert_equal(1, #problems, "a cycle is reported once, not once per member")
  self:assert_equal("a,b,a", table.concat(problems[1].context.path, ","))
end

function T:test_a_cycle_of_many_keys_ignores_the_entry_chain()
  local c = container.Container()
    :bind("entry", thing, { lifetime = "transient", requires = { "a" } })
    :bind("a", thing, { lifetime = "transient", requires = { "b" } })
    :bind("b", thing, { lifetime = "transient", requires = { "c" } })
    :bind("c", thing, { lifetime = "transient", requires = { "d" } })
    :bind("d", thing, { lifetime = "transient", requires = { "b" } })
  local problems = problems_of(c)
  self:assert_equal(1, #problems)
  self:assert_equal("b,c,d,b", table.concat(problems[1].context.path, ","))
  self:assert_true(problems[1].message:find("b -> c -> d -> b", 1, true) ~= nil)
end

function T:test_a_singleton_that_requires_a_scoped_service_is_rejected()
  local c = container.Container()
    :bind("s", thing, { lifetime = "singleton", requires = { "r" } })
    :bind("r", thing, { lifetime = "scoped" })
  local problems = problems_of(c)
  self:assert_true(core.is_instance_of(problems[1], container.LifetimeError))
  self:assert_equal("s", problems[1].context.key)
  self:assert_equal("r", problems[1].context.dependency)
  self:assert_equal("s,r", table.concat(problems[1].context.path, ","))
end

function T:test_a_singleton_reaches_a_scoped_service_through_transients()
  local c = container.Container()
    :bind("s", thing, { lifetime = "singleton", requires = { "t1" } })
    :bind("t1", thing, { lifetime = "transient", requires = { "t2" } })
    :bind("t2", thing, { lifetime = "transient", requires = { "r" } })
    :bind("r", thing, { lifetime = "scoped" })
  local problems = problems_of(c)
  self:assert_equal(1, #problems)
  self:assert_equal("s,t1,t2,r", table.concat(problems[1].context.path, ","))
end

function T:test_a_captive_dependency_reached_directly_and_through_a_transient_is_reported_once()
  local c = container.Container()
    :bind("s", thing, { lifetime = "singleton", requires = { "r", "t" } })
    :bind("t", thing, { lifetime = "transient", requires = { "r" } })
    :bind("r", thing, { lifetime = "scoped" })
  local problems = problems_of(c)
  self:assert_equal(1, #problems)
  self:assert_equal("s,r", table.concat(problems[1].context.path, ","))
end

function T:test_the_other_lifetime_combinations_are_accepted()
  local c = container.Container()
    :bind("sing", thing, { lifetime = "singleton" })
    :bind("tran", thing, { lifetime = "transient", requires = { "scop" } })
    :bind("scop", thing, { lifetime = "scoped", requires = { "sing", "tran2" } })
    :bind("tran2", thing, { lifetime = "transient", requires = { "sing" } })
    :bind("sing2", thing, { lifetime = "singleton", requires = { "tran2", "sing" } })
  c:validate()
end

function T:test_a_class_that_does_not_implement_its_interface_is_a_problem()
  local Repo = core.interface("Repo", { "find" })
  local Good = core.class("Good", nil, { implements = { Repo } })
  function Good:find() end
  core.finalise(Good)
  container.Container():bind(Repo, Good, { lifetime = "transient" }):validate()
  local problems = problems_of(container.Container():bind(Repo, Thing, { lifetime = "transient" }))
  self:assert_true(core.is_instance_of(problems[1], core.ConformanceError))
  self:assert_equal("Repo", problems[1].context.key)
end

function T:test_every_problem_is_collected_in_the_order_of_binding()
  local Repo = core.interface("Repo2", { "find" })
  local c = container.Container()
    :bind("a", thing, { lifetime = "transient", requires = { "ghost" } })
    :bind("s", thing, { lifetime = "singleton", requires = { "r" } })
    :bind("r", thing, { lifetime = "scoped" })
    :bind(Repo, Thing, { lifetime = "transient" })
    :bind("x", thing, { lifetime = "transient", requires = { "y" } })
    :bind("y", thing, { lifetime = "transient", requires = { "x" } })
  local problems, err = problems_of(c)
  self:assert_equal(4, #problems)
  local expected = { container.MissingBindingError, container.LifetimeError, core.ConformanceError, container.CycleError }
  for i, class in ipairs(expected) do self:assert_true(core.is_instance_of(problems[i], class), "problem " .. i) end
  self:assert_true(err.message:find("4 problems", 1, true) ~= nil)
  self:assert_true(err.message:find(problems[1].message, 1, true) ~= nil)
end

function T:test_the_diagnostic_is_deterministic()
  local function run()
    local c = container.Container()
    for i = 1, 6 do c:bind("k" .. i, thing, { lifetime = "transient", requires = { "m" .. i } }) end
    local _, err = problems_of(c)
    return err.message
  end
  self:assert_equal(run(), run())
end

function T:test_interface_keys_are_rendered_by_name_and_never_by_address()
  local Repo = core.interface("Users", { "find" })
  local c = container.Container():bind("a", thing, { lifetime = "transient", requires = { Repo } })
  local problems = problems_of(c)
  self:assert_equal("Users", problems[1].context.key)
  self:assert_true(problems[1].message:find("0x", 1, true) == nil)
end

function T:test_validate_freezes_the_container()
  local c = container.Container():bind("a", thing, { lifetime = "transient" })
  c:validate()
  local err = self:assert_error(function() c:bind("b", thing, { lifetime = "transient" }) end)
  self:assert_true(core.is_instance_of(err, container.ContainerError))
  err = self:assert_error(function() c:override("a", thing) end)
  self:assert_true(core.is_instance_of(err, container.ContainerError))
end

function T:test_a_failed_validation_does_not_freeze()
  local c = container.Container():bind("a", thing, { lifetime = "transient", requires = { "b" } })
  self:assert_error(function() c:validate() end)
  c:bind("b", thing, { lifetime = "transient" })
  c:validate()
end

function T:test_resolution_and_scopes_need_validation_first()
  local c = container.Container():bind("a", thing, { lifetime = "transient" })
  local err = self:assert_error(function() c:resolve("a") end)
  self:assert_true(core.is_instance_of(err, container.ContainerError))
  err = self:assert_error(function() c:open_scope() end)
  self:assert_true(core.is_instance_of(err, container.ContainerError))
end

function T:test_an_override_cannot_introduce_a_cycle_or_a_violation_unnoticed()
  local c = container.Container()
    :bind("a", thing, { lifetime = "singleton" })
    :bind("r", thing, { lifetime = "scoped" })
  c:override("a", thing, { lifetime = "singleton", requires = { "r" } })
  local problems = problems_of(c)
  self:assert_true(core.is_instance_of(problems[1], container.LifetimeError))
  local d = container.Container():bind("a", thing, { lifetime = "transient" }):bind("b", thing, { lifetime = "transient", requires = { "a" } })
  d:override("a", thing, { lifetime = "transient", requires = { "b" } })
  self:assert_true(core.is_instance_of(problems_of(d)[1], container.CycleError))
end

-- Warnings ----------------------------------------------------------------------------------------------------------

function T:test_a_singleton_over_a_transient_is_a_warning_and_validation_succeeds()
  local c = container.Container()
    :bind("s", thing, { lifetime = "singleton", requires = { "t" } })
    :bind("t", thing, { lifetime = "transient" })
  local returned, warnings = c:validate()
  self:assert_true(returned == c)
  self:assert_equal(1, #warnings)
  local w = warnings[1]
  self:assert_equal("singleton_over_transient", w.code)
  self:assert_equal("s", w.key)
  self:assert_equal("t", w.dependency)
  self:assert_equal("s", w.path[1])
  self:assert_equal("t", w.path[2])
  self:assert_true(w.message:find('"s"', 1, true) ~= nil and w.message:find('"t"', 1, true) ~= nil)
  self:assert_true(w.message:find("built once", 1, true) ~= nil)
  self:assert_equal(1, #select(2, c:validate()), "a later call returns the same warnings")
  c:resolve("s")
end

function T:test_a_singleton_through_a_singleton_is_checked_on_its_own_without_duplicates()
  local Repo = core.interface("Repo", { "find" })
  local c = container.Container()
    :bind("outer", thing, { lifetime = "singleton", requires = { "inner" } })
    :bind("inner", thing, { lifetime = "singleton", requires = { Repo } })
    :bind(Repo, function() return { find = function() end } end, { lifetime = "transient" })
  local _, warnings = c:validate()
  self:assert_equal(1, #warnings)
  self:assert_equal("inner", warnings[1].key)
  self:assert_equal("Repo", warnings[1].dependency)
end

function T:test_a_scoped_service_over_a_transient_and_clean_graphs_give_no_warning()
  local c = container.Container()
    :bind("r", thing, { lifetime = "scoped", requires = { "t" } })
    :bind("t", thing, { lifetime = "transient" })
    :bind("s", thing, { lifetime = "singleton" })
  local _, warnings = c:validate()
  self:assert_equal(0, #warnings)
end

return T
