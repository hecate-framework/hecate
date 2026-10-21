-- json.null, json.array and json.object: identity, immutability and the marker functions.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonMarkersTest")

function T:test_null_is_a_single_immutable_value_that_is_not_nil_or_false()
  self:assert_not_nil(json.null)
  self:assert_true(json.null ~= false)
  self:assert_equal("json.null", tostring(json.null))
  self:assert_error(function() ---@diagnostic disable-next-line: inject-field
    json.null.x = 1 end, "immutable")
  self:assert_equal(nil, next(json.null))
  self:assert_true(json.decode("null") == json.null)
  self:assert_true(json.decode("[null]")[1] == json.null)
end

function T:test_array_and_object_return_the_given_table_marked()
  local items = { 1, 2 }
  self:assert_true(json.array(items) == items)
  self:assert_true(json.is_array(items))
  self:assert_false(json.is_object(items))
  local members = { a = 1 }
  self:assert_true(json.object(members) == members)
  self:assert_true(json.is_object(members))
  self:assert_false(json.is_array(members))
end

function T:test_array_and_object_create_an_empty_table_without_argument()
  local array, object = json.array(), json.object()
  self:assert_true(json.is_array(array) and next(array) == nil)
  self:assert_true(json.is_object(object) and next(object) == nil)
  self:assert_true(json.array() ~= json.array())
end

function T:test_the_marker_can_be_changed_but_a_foreign_metatable_is_never_replaced()
  local t = json.array({})
  json.object(t)
  self:assert_true(json.is_object(t))
  local foreign = setmetatable({}, { __index = {} })
  local err = self:assert_error(function() json.array(foreign) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_error(function() ---@diagnostic disable-next-line: param-type-mismatch
    json.object("x") end)
  self:assert_error(function() ---@diagnostic disable-next-line: param-type-mismatch
    json.array(1) end)
end

function T:test_is_array_and_is_object_accept_any_value()
  for _, value in ipairs({ 1, "x", true, {}, json.null }) do
    self:assert_false(json.is_array(value))
    self:assert_false(json.is_object(value))
  end
  self:assert_false(json.is_array(nil))
end

function T:test_markers_do_not_add_keys_to_the_table()
  local items = json.array({ 1, 2, 3 })
  local count = 0
  for _ in pairs(items) do count = count + 1 end
  self:assert_equal(3, count)
  self:assert_equal(3, #items)
end

return T
