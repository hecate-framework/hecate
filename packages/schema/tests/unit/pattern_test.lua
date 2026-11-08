---@diagnostic disable: need-check-nil, param-type-mismatch
local test = require("harness.test")
local core = require("hecate.core")
local translate = require("hecate.schema.pattern")
local schema = require("hecate.schema")
local T = test.Case("SchemaPatternTest")

local function is_refused(lua_pattern)
  local ok, err = pcall(translate.to_ecma, lua_pattern)
  return not ok and core.is_instance_of(err, core.ArgumentError)
end

function T:test_literals_and_anchors()
  self:assert_equal(translate.to_ecma("abc"), "abc")
  self:assert_equal(translate.to_ecma("^abc$"), "^abc$")
  self:assert_equal(translate.to_ecma("a^b$c"), "a\\^b\\$c")
  self:assert_equal(translate.to_ecma("a{2}|b"), "a\\{2\\}\\|b")
  self:assert_equal(translate.to_ecma("a/b"), "a\\/b")
  self:assert_equal(translate.to_ecma(""), "")
end

function T:test_dot_and_classes()
  self:assert_equal(translate.to_ecma("."), "[\\s\\S]")
  self:assert_equal(translate.to_ecma("%d+"), "[0-9]+")
  self:assert_equal(translate.to_ecma("%a"), "[A-Za-z]")
  self:assert_equal(translate.to_ecma("%D"), "[^0-9]")
  self:assert_equal(translate.to_ecma("%s"), "[ \\t\\n\\x0B\\f\\r]")
  self:assert_equal(translate.to_ecma("%w"), "[A-Za-z0-9]")
end

function T:test_escapes()
  self:assert_equal(translate.to_ecma("%."), "\\.")
  self:assert_equal(translate.to_ecma("%%"), "%")
  self:assert_equal(translate.to_ecma("%-"), "-")
end

function T:test_quantifiers()
  self:assert_equal(translate.to_ecma("a*b+c?"), "a*b+c?")
  self:assert_equal(translate.to_ecma("a-b"), "a*?b")
  self:assert_equal(translate.to_ecma("*a"), "\\*a")
  self:assert_equal(translate.to_ecma("-a"), "-a")
  self:assert_equal(translate.to_ecma("(ab)*"), "(ab)\\*")
end

function T:test_sets()
  self:assert_equal(translate.to_ecma("[abc]"), "[abc]")
  self:assert_equal(translate.to_ecma("[^a-z]"), "[^a-z]")
  self:assert_equal(translate.to_ecma("[%d_]"), "[0-9_]")
  self:assert_equal(translate.to_ecma("[a-]"), "[a\\x2D]")
  self:assert_equal(translate.to_ecma("[]a]"), "[\\x5Da]")
  self:assert_equal(translate.to_ecma("[%]]"), "[\\x5D]")
  self:assert_equal(translate.to_ecma("[%^]"), "[\\x5E]")
end

function T:test_groups_and_backreferences()
  self:assert_equal(translate.to_ecma("(a)(b)%1"), "(a)(b)(?:\\1)")
  self:assert_equal(translate.to_ecma("(^a)"), "(\\^a)")
end

function T:test_refusals()
  for _, p in ipairs({ "%bxy", "%f[a]", "()", "caf\xC3\xA9", "(a", "a)", "[a", "a%", "%z", "[%S]", "%1", "(a)%2" }) do
    self:assert_true(is_refused(p), "should refuse " .. p)
  end
end

-- Differential check: for ASCII inputs, the emitted expression must accept exactly what Lua accepts. The reference is a
-- small independent backtracking matcher over the ECMA subset we emit (no regex library in Lua), in tests/support/ecma.lua.
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local ecma_matches = dofile(here .. "/../support/ecma.lua").matches

function T:test_differential_against_lua()
  local patterns = { "^%d+$", "%a%w*", "^[%a_][%w_]*$", "a-b", "^a-$", "x*y", "[^%s]+", "^(ab)c$", "%.%-", "a?b?c",
    "^[a-f%d]+$", "%u%l", ".-z", "^$", "[%p]", "[^%d%.]", "a*$" }
  local subjects = { "", "a", "ab", "abc", "abz", "123", "12a", "a_1", "_x9", "x y", "yy", "xxy", "A", "Ab", "a.-b",
    "zz", "5.5", "f0f0", "!", "ab-", "aaa", "b", "c", "ac", "bc" }
  for _, p in ipairs(patterns) do
    local re = translate.to_ecma(p)
    for _, s in ipairs(subjects) do
      self:assert_equal(ecma_matches(re, s), s:find(p) ~= nil, ("pattern %q (%s) on %q"):format(p, re, s))
    end
  end
end

function T:test_emission_uses_the_translator()
  local emitted = schema.string({ pattern = "^%d+$" }):to_json_schema()
  self:assert_equal(emitted.pattern, "^[0-9]+$")
  local nested = schema.object({ a = schema.array(schema.string({ pattern = "x" })) }):to_json_schema()
  self:assert_equal(nested.properties.a.items.pattern, "x")
  local ok, err = pcall(function() return schema.string({ pattern = "%bxy" }):to_json_schema() end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_declaration_warns_through_the_given_logger()
  local warnings = {}
  local logger = { warning = function(_, message, fields) warnings[#warnings + 1] = { message, fields } end }
  schema.string({ pattern = "^%d+$", logger = logger })
  self:assert_equal(0, #warnings)
  local s = schema.string({ pattern = "%bxy", logger = logger })
  self:assert_equal(1, #warnings)
  self:assert_equal("%bxy", warnings[1][2].pattern)
  self:assert_equal(nil, (s.options --[[@as table]]).logger)
  self:assert_false(pcall(function() return s:to_json_schema() end))
  -- without a logger nothing is reported and declaration succeeds
  schema.string({ pattern = "%bxy" })
end

return T
