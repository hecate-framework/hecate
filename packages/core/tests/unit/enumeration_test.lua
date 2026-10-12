local test = require("harness.test")
local core = require("hecate.core")
local T = test.Case("EnumerationTest")

function T:test_values_are_members_of_the_enumeration()
  local Status = core.enumeration("Status", { "active", "disabled" })
  self:assert_equal("active", Status.active.name)
  self:assert_equal(1, Status.active.ordinal)
  self:assert_equal(2, Status.disabled.ordinal)
end

function T:test_tostring_of_value_and_enumeration()
  local Status = core.enumeration("Status", { "active", "disabled" })
  self:assert_equal("active", tostring(Status.active))
  self:assert_equal("enumeration Status", tostring(Status))
end

function T:test_values_are_singletons_compared_by_identity()
  local Status = core.enumeration("Status", { "active", "disabled" })
  self:assert_true(Status.active == Status:find("active"))
  self:assert_false(Status.active == Status.disabled)
end

function T:test_values_are_frozen()
  local Status = core.enumeration("Status", { "active" })
  self:assert_error(function() Status.active.name = "x" end)
end

function T:test_enumeration_is_closed()
  local Status = core.enumeration("Status", { "active" })
  self:assert_error(function() Status.other = 1 end)
  self:assert_error(function() Status.active = 1 end)
  self:assert_equal("table", type(Status.active))
end

function T:test_membership()
  local Status = core.enumeration("Status", { "active", "disabled" })
  local Other = core.enumeration("Other", { "active" })
  self:assert_true(Status:contains(Status.active))
  self:assert_false(Status:contains(Other.active))
  self:assert_false(Status:contains("active"))
  self:assert_false(Status:contains(nil))
end

function T:test_find_returns_nil_for_absence()
  local Status = core.enumeration("Status", { "active" })
  self:assert_nil(Status:find("nope"))
  self:assert_nil(Status:find(3))
end

function T:test_values_and_names_are_ordered_copies()
  local Status = core.enumeration("Status", { "b", "a", "c" })
  local names = Status:names()
  self:assert_equal("b", names[1])
  self:assert_equal("c", names[3])
  names[1] = "zzz"
  self:assert_equal("b", Status:names()[1])
  self:assert_true(Status:values()[2] == Status.a)
  self:assert_equal(3, Status:size())
  self:assert_equal(3, #Status)
end

function T:test_pairs_iterates_in_declaration_order()
  local Status = core.enumeration("Status", { "b", "a" })
  local order = {}
  for name, value in pairs(Status) do order[#order + 1] = name .. value.ordinal end
  self:assert_equal("b1", order[1])
  self:assert_equal("a2", order[2])
end

function T:test_introspection()
  local Status = core.enumeration("Status", { "active" })
  self:assert_true(core.is_enumeration(Status))
  self:assert_false(core.is_enumeration({}))
  self:assert_equal("Status", core.name(Status))
  self:assert_equal("Status", Status.active.enumeration)
end

function T:test_invalid_definitions_raise_argument_errors()
  local function bad(name, list)
    local err = self:assert_error(function() core.enumeration(name, list) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
  bad(1, { "a" })
  bad("E", "a")
  bad("E", {})
  bad("E", { "a", "a" })
  bad("E", { "" })
  bad("E", { 1 })
  bad("E", { "values" })
  bad("E", { "find" })
end

function T:test_value_lookup_is_a_plain_table_read()
  local Status = core.enumeration("Status", { "active" })
  self:assert_equal("table", type(getmetatable(Status).__index))
end

return T
