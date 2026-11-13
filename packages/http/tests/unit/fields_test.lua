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

-- Review H-1: the trimming is linear in the length of the value; a lazy capture before a greedy class of whitespace
-- (`^[ \t]*(.-)[ \t]*$`) was quadratic and let one head stall the reactor thread.
function T:test_trimming_keeps_inner_whitespace_and_empties_a_blank_value()
  local f = http.Fields()
  f:add("A", "  a \t b  "):add("B", " \t \t "):add("C", ""):add("D", "x")
  self:assert_equal("a \t b", f:get("a"))
  self:assert_equal("", f:get("b"))
  self:assert_equal("", f:get("c"))
  self:assert_equal("x", f:get("d"))
  f:set("A", "\t y \t")
  self:assert_equal("y", f:get("a"))
end

function T:test_trimming_a_whitespace_heavy_value_is_linear()
  local shapes = {
    "a" .. (" "):rep(8000) .. "b",
    "a" .. (" \t"):rep(4000),
    (" "):rep(8000),
    (" \t"):rep(2000) .. "a" .. (" "):rep(4000) .. "b" .. ("\t"):rep(2000),
  }
  local started = os.clock()
  for _ = 1, 10 do
    for _, value in ipairs(shapes) do
      local f = http.Fields()
      f:add("X", value)
      f:set("Y", value)
    end
  end
  local elapsed = os.clock() - started
  -- The quadratic trim took 6.4 s here; linear takes milliseconds. 0.5 s leaves room for slow CI runners (Windows).
  self:assert_true(elapsed < 0.5, ("80 trims of 8 KiB values took %.3f s"):format(elapsed))
end

-- Review H-3: the constructor of the parser trusts llhttp for the names and for the other control characters (refused
-- by the parser: the field vectors of tests/conformance/rfc9112_test.lua), and keeps the check against CR, LF and NUL.
function T:test_the_parser_constructor_keeps_the_check_against_control_characters()
  local fields = http.Fields._of_parsed({ "Host", "h", "X-A", "v \t", "x-a", "\t" }) --[[@as hecate.http.Fields]]
  self:assert_equal("v", fields:get("x-a"))
  self:assert_equal(2, #fields:get_all("X-A"))
  self:assert_equal("", fields:get_all("x-a")[2])
  for _, bad in ipairs({ "a\rb", "a\nb", "a\0b", "\r\n", "a\0" }) do
    self:assert_nil(http.Fields._of_parsed({ "X", bad }), ("%q"):format(bad))
  end
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

function T:test_control_characters_other_than_tab_are_refused_in_values()
  local f = http.Fields()
  f:add("X-Tab", "a\tb")
  self:assert_equal("a\tb", f:get("X-Tab"))
  for _, value in ipairs({ "a\1b", "a\27[31m", "a\127b", "a\0b", "a\rb", "a\nb", "a\31b" }) do
    self:assert_error(function() f:add("X-Bad", value) end)
  end
  self:assert_error(function() http.MediaType.parse("text/plain; charset=a"):set_parameter("x", "a\1b") end)
end

return T
