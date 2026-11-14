local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("ProblemTest")

--- Declares a class implementing Problem, with the given class-level members.
---@param name string
---@param members table
---@param superclass? table
---@return table
local function declare(name, members, superclass)
  local class = core.class(name, superclass, { implements = { core.Problem } })
  for key, value in pairs(members) do class[key] = value end
  return class
end

--- A class-level function returning `value`.
local function returning(value) return function() return value end end

function T:test_class_with_status_and_title_functions_finalises()
  local NotFound = declare("NotFound", { status = returning(404), title = returning("Not Found") })
  core.finalise(NotFound)
  self:assert_true(core.implements(NotFound, core.Problem))
  self:assert_true(core.is_interface(core.Problem))
  self:assert_equal(404, NotFound.status())
  self:assert_equal("Not Found", NotFound.title())
end

function T:test_problem_requires_methods_only()
  local Bad = declare("Bad", {})
  local err = self:assert_error(function() core.finalise(Bad) end)
  self:assert_true(err.message:find("missing method status", 1, true) ~= nil)
end

function T:test_missing_members_are_named_with_class_and_interface()
  local Bad = declare("Bad", {})
  local err = self:assert_error(function() core.finalise(Bad) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_equal("Bad", err.context.class)
  self:assert_true(err.message:find("Bad", 1, true) ~= nil)
  self:assert_true(err.message:find("status", 1, true) ~= nil)
  self:assert_true(err.message:find("title", 1, true) ~= nil)
  self:assert_true(err.message:find("Problem", 1, true) ~= nil)
  self:assert_equal(2, #err.context.missing)
  self:assert_equal("status", err.context.missing[1].member)
  self:assert_equal("Problem", err.context.missing[1].origin)
  self:assert_equal("title", err.context.missing[2].member)
end

function T:test_a_datum_is_not_a_method()
  local Bad = declare("Bad", { status = 404, title = "Not Found" })
  local err = self:assert_error(function() core.finalise(Bad) end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_equal(2, #err.context.missing)
end

function T:test_returned_values_are_not_checked_at_finalisation()
  -- Like Representable.schema(): finalise checks presence, never calls the user's functions.
  local called = false
  local Odd = declare("Odd", {
    status = function() called = true return 200 end,
    title = function() called = true return "" end,
  })
  core.finalise(Odd)
  self:assert_false(called)
end

function T:test_members_inherited_from_a_finalised_superclass_count()
  local Base = declare("Base", { status = returning(409), title = returning("Conflict") })
  core.finalise(Base)
  local Child = core.class("Child", Base, { implements = { core.Problem } })
  core.finalise(Child)
  self:assert_equal(409, Child.status())
  self:assert_true(core.implements(Child, core.Problem))
end

return T
