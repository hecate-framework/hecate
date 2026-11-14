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

function T:test_class_with_status_and_title_finalises()
  local NotFound = declare("NotFound", { status = 404, title = "Not Found" })
  core.finalise(NotFound)
  self:assert_true(core.implements(NotFound, core.Problem))
  self:assert_true(core.is_interface(core.Problem))
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

function T:test_status_must_be_an_integer_from_100_to_599()
  for _, value in ipairs({ 99, 600, 404.5, "404", true }) do
    local Bad = declare("Bad", { status = value, title = "T" })
    local err = self:assert_error(function() core.finalise(Bad) end)
    self:assert_equal("hecate.core.ConformanceError", err.code)
    self:assert_equal(1, #err.context.missing, tostring(value))
    self:assert_equal("status", err.context.missing[1].member)
  end
  for _, value in ipairs({ 100, 599 }) do
    core.finalise(declare("Edge" .. value, { status = value, title = "T" }))
  end
end

function T:test_title_must_be_a_string()
  local Bad = declare("Bad", { status = 400, title = 12 })
  local err = self:assert_error(function() core.finalise(Bad) end)
  self:assert_equal("title", err.context.missing[1].member)
  self:assert_true(err.message:find("string", 1, true) ~= nil)
end

function T:test_members_inherited_from_a_finalised_superclass_count()
  local Base = declare("Base", { status = 409, title = "Conflict" })
  core.finalise(Base)
  local Child = core.class("Child", Base, { implements = { core.Problem } })
  core.finalise(Child)
  self:assert_equal(409, Child.status)
  self:assert_true(core.implements(Child, core.Problem))
end

function T:test_a_function_is_not_a_field()
  local Bad = declare("Bad", { status = function() return 400 end, title = "T" })
  self:assert_error(function() core.finalise(Bad) end)
end

function T:test_failed_finalisation_leaves_the_class_unfinalised()
  local Bad = declare("Bad", { status = 700, title = "T" })
  self:assert_error(function() core.finalise(Bad) end)
  self:assert_false(core.is_finalised(Bad))
end

return T
