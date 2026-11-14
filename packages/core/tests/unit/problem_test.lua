local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("ProblemTest")

-- `core.Problem` is a marker interface: it declares no method and no field. The attributes `status` and `title`
-- are a documented contract validated by the consumer, so nothing here checks them.

function T:test_an_interface_with_an_empty_method_list_is_accepted()
  local Marker = core.interface("Marker", {})
  self:assert_true(core.is_interface(Marker))
  local Tagged = core.class("Tagged", nil, { implements = { Marker } })
  core.finalise(Tagged)
  self:assert_true(core.implements(Tagged, Marker))
end

function T:test_problem_is_an_interface()
  self:assert_true(core.is_interface(core.Problem))
  self:assert_equal("interface Problem", tostring(core.Problem))
end

function T:test_a_class_declaring_problem_finalises_without_any_member()
  local Failure = core.class("Failure", nil, { implements = { core.Problem } })
  core.finalise(Failure)
  self:assert_true(core.implements(Failure, core.Problem))
end

function T:test_attributes_are_data_and_not_checked_at_finalisation()
  local NotFound = core.class("NotFound", nil, { implements = { core.Problem } })
  NotFound.status = 404
  NotFound.title = "Not Found"
  core.finalise(NotFound)
  self:assert_true(core.implements(NotFound, core.Problem))
  self:assert_equal(404, NotFound.status)
  self:assert_equal("Not Found", NotFound.title)
end

function T:test_a_subclass_inherits_the_declaration()
  local Base = core.class("Base", nil, { implements = { core.Problem } })
  Base.status = 500
  Base.title = "Internal Server Error"
  core.finalise(Base)
  local Child = core.class("Child", Base)
  Child.status = 409
  core.finalise(Child)
  self:assert_true(core.implements(Child, core.Problem))
  self:assert_equal(409, Child.status)
  local Grandchild = core.class("Grandchild", Child)
  core.finalise(Grandchild)
  self:assert_true(core.implements(Grandchild, core.Problem))
  self:assert_true(core.implements(Grandchild(), core.Problem))
end

function T:test_a_class_that_does_not_declare_it_is_not_a_problem()
  local Plain = core.class("Plain")
  Plain.status = 404
  Plain.title = "Not Found"
  core.finalise(Plain)
  self:assert_false(core.implements(Plain, core.Problem))
end

return T
