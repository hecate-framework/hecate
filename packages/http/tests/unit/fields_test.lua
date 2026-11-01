---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local http = require("hecate.http")
local core = require("hecate.core")
local T = test.Case("FieldsTest")

function T:test_names_are_case_insensitive()
  local f = http.Fields()
  f:add("Content-Type", "text/plain")
  self:assert_equal("text/plain", f:get("content-type"))
  self:assert_equal("text/plain", f:get("CONTENT-TYPE"))
  self:assert_true(f:has("cOnTeNt-TyPe"))
end

function T:test_order_and_original_names_are_preserved()
  local f = http.Fields({ { "X-B", "1" }, { "x-a", "2" }, { "X-B", "3" } })
  local seen = {}
  for name, value in f:lines() do seen[#seen + 1] = name .. "=" .. value end
  self:assert_equal("X-B=1,x-a=2,X-B=3", table.concat(seen, ","))
  self:assert_equal(3, f:count())
end

function T:test_multi_value_get_all_and_combined()
  local f = http.Fields({ { "Accept", "a" }, { "accept", "b" } })
  self:assert_equal("a", f:get("Accept"))
  self:assert_equal("a,b", table.concat(f:get_all("ACCEPT"), ","))
  self:assert_equal("a, b", f:combined("Accept"))
  self:assert_nil(f:combined("Missing"))
end

function T:test_set_cookie_is_never_combined()
  local f = http.Fields({ { "Set-Cookie", "a=1" }, { "Set-Cookie", "b=2" } })
  self:assert_equal(2, #f:get_all("set-cookie"))
  local err = self:assert_error(function() f:combined("Set-Cookie") end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_set_replaces_at_first_position()
  local f = http.Fields({ { "A", "1" }, { "B", "2" }, { "a", "3" } })
  f:set("A", "9")
  local seen = {}
  for name, value in f:lines() do seen[#seen + 1] = name .. "=" .. value end
  self:assert_equal("A=9,B=2", table.concat(seen, ","))
end

function T:test_remove_and_copy_are_independent()
  local f = http.Fields({ { "A", "1" }, { "a", "2" }, { "B", "3" } })
  local copy = f:copy()
  self:assert_equal(2, f:remove("A"))
  self:assert_nil(f:get("a"))
  self:assert_equal("1", copy:get("a"))
end

function T:test_values_are_trimmed()
  local f = http.Fields()
  f:add("X", " \t v \t ")
  self:assert_equal("v", f:get("x"))
end

function T:test_injection_is_refused()
  local f = http.Fields()
  self:assert_error(function() f:add("X", "a\r\nSet-Cookie: x=1") end)
  self:assert_error(function() f:add("X", "a\nb") end)
  self:assert_error(function() f:add("X", "a\0b") end)
  self:assert_error(function() f:add("Bad Name", "v") end)
  self:assert_error(function() f:add("X:", "v") end)
  self:assert_error(function() f:set("", "v") end)
  local err = self:assert_error(function() f:add("X", "a\rb") end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_map_initialiser()
  local f = http.Fields({ Accept = { "a", "b" }, Host = "h" })
  self:assert_equal("a, b", f:combined("accept"))
  self:assert_equal("h", f:get("host"))
end

return T
