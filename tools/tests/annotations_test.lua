local test = require("harness.test")
local annotations = require("lib.annotations")
local T = test.Case("AnnotationsTest")

local function scan(source) return annotations.scan("global <const> require\n" .. source) end

local CLASS = "--- A module.\n---@class hecate.x\nlocal M = {}\n\n"

function T:test_clean_module()
  local src = CLASS .. "--- Adds.\n---@param a integer\n---@param b integer\n---@return integer\n"
    .. "function M.add(a, b) return a + b end\n\nreturn M\n"
  self:assert_equal(0, #scan(src))
end

function T:test_missing_block()
  local hits = scan(CLASS .. "function M.f(a) return a end\n\nreturn M\n")
  self:assert_equal(1, #hits)
  self:assert_equal("M.f", hits[1].name)
end

function T:test_missing_param_and_return()
  local hits = scan(CLASS .. "--- Doc.\n---@param a integer\nfunction M.f(a, b) return a end\n\nreturn M\n")
  self:assert_equal(2, #hits)
end

function T:test_methods_skip_self_and_varargs_need_a_param()
  local ok = scan(CLASS .. "--- Doc.\nfunction M:f() end\n\nreturn M\n")
  self:assert_equal(0, #ok)
  local bad = scan(CLASS .. "--- Doc.\nfunction M.g(...) end\n\nreturn M\n")
  self:assert_equal(1, #bad)
end

function T:test_assigned_function_is_checked()
  self:assert_equal(1, #scan(CLASS .. "--- Doc.\nM.f = function(a) end\n\nreturn M\n"))
end

function T:test_absence_requires_nullable_return()
  local bad = scan(CLASS .. "--- Doc.\n---@param a any\n---@return integer\nfunction M.f(a)\n  if a then return nil end\n  return 1\nend\n\nreturn M\n")
  self:assert_equal(1, #bad)
  local good = scan(CLASS .. "--- Doc.\n---@param a any\n---@return integer?\nfunction M.f(a)\n  if a then return nil end\n  return 1\nend\n\nreturn M\n")
  self:assert_equal(0, #good)
  local union = scan(CLASS .. "--- Doc.\n---@return integer|nil  the value\nfunction M.f()\n  return nil\nend\n\nreturn M\n")
  self:assert_equal(0, #union)
end

function T:test_nested_function_returns_are_not_attributed()
  local src = CLASS .. "--- Doc.\nfunction M.f()\n  local g = function() return nil end\n  g()\nend\n\nreturn M\n"
  self:assert_equal(0, #scan(src))
end

function T:test_returns_in_strings_and_comments_are_ignored()
  local src = CLASS .. "--- Doc.\nfunction M.f()\n  local s = 'return nil end'\n  -- return 1\nend\n\nreturn M\n"
  self:assert_equal(0, #scan(src))
end

function T:test_private_and_underscore_are_not_exported()
  local src = CLASS .. "function M._hidden(a) return a end\n---@private\nfunction M.other(a) return a end\n\nreturn M\n"
  self:assert_equal(0, #scan(src))
end

function T:test_other_tables_and_indented_functions_are_not_seen()
  local src = CLASS .. "local helpers = {}\nfunction helpers.f(a) return a end\nlocal function g(a) return a end\n\nreturn M\n"
  self:assert_equal(0, #scan(src))
end

function T:test_exception_comment()
  self:assert_equal(0, #scan(CLASS .. "function M.f(a) return a end -- annotations-ok\n\nreturn M\n"))
end

function T:test_returned_table_needs_a_class_when_it_exports()
  local hits = scan("local M = {}\n\n--- Doc.\nfunction M.f() end\n\nreturn M\n")
  self:assert_equal(1, #hits)
  self:assert_equal("M", hits[1].name)
  self:assert_equal(0, #scan("local M = {}\n\nreturn M\n"))
end

function T:test_class_constructor_return_is_recognised()
  local src = "--- A.\n---@class hecate.A\nlocal A = core.class(\"A\")\n\nfunction A:run() end\n\nreturn core.finalise(A)\n"
  self:assert_equal(1, #scan(src))
end

function T:test_field_needs_a_comment()
  self:assert_equal(1, #scan(CLASS .. "M.LIMIT = 10\n\nreturn M\n"))
  self:assert_equal(0, #scan(CLASS .. "--- The limit.\nM.LIMIT = 10\n\nreturn M\n"))
  self:assert_equal(0, #scan(CLASS .. "M.alias = other.alias\n\nreturn M\n"))
end

function T:test_crlf_sources()
  local src = (CLASS .. "--- Doc.\n---@param a integer\n---@return integer?\nfunction M.f(a)\n  return nil\nend\n\nreturn M\n"):gsub("\n", "\r\n")
  self:assert_equal(0, #scan(src))
end

return T
