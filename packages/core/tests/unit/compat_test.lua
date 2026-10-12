local test = require("harness.test")
local compat = require("hecate.core.compat")
local T = test.Case("CompatTest")

function T:test_table_create_returns_empty_table()
  local t = compat.table_create(4, 2)
  self:assert_equal("table", type(t))
  self:assert_nil(next(t))
end

function T:test_table_create_defaults()
  self:assert_equal("table", type(compat.table_create()))
end

function T:test_table_create_is_usable_as_array()
  local t = compat.table_create(3, 0)
  for i = 1, 3 do t[i] = i end
  self:assert_equal(3, #t)
end

function T:test_lua_version_is_reported()
  self:assert_equal("5.5", compat.lua_version)
end

return T
