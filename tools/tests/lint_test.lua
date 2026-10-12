local test = require("harness.test")
local lint = require("lib.lint")
local T = test.Case("LintTest")

local function check(source) return lint.check_source(source, "fixture") end

function T:test_clean_chunk() self:assert_equal(0, #check("global <const> print\nprint(1)\n")) end
function T:test_missing_global_declaration() self:assert_equal(1, #check("local a = 1\n")) end
function T:test_global_write_rejected() self:assert_equal(1, #check("global <const> print\nb = 2\n")) end
function T:test_syntax_error() self:assert_equal(1, #check("global <const> print\nprint(\n")) end
return T
