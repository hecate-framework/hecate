local test = require("harness.test")
local constructs = require("lib.constructs")
local T = test.Case("ConstructsTest")

local function count(src, allow) return #constructs.scan(src, allow or false) end

function T:test_read_declarations_allowed()
  self:assert_equal(0, count("global <const> print, pairs\nglobal <const> *\nglobal x\n"))
end
function T:test_global_definitions_rejected()
  self:assert_equal(1, count("global function f() end\n"))
  self:assert_equal(1, count("global y = 1\n"))
end
function T:test_table_create_only_in_compat()
  self:assert_equal(1, count("local t = table.create(1, 2)\n"))
  self:assert_equal(0, count("local t = table.create(1, 2)\n", true))
end
function T:test_collectgarbage_param() self:assert_equal(1, count('collectgarbage("param", "pause", 1)\n')) end
function T:test_comments_ignored() self:assert_equal(0, count("-- global function f\n")) end
return T
