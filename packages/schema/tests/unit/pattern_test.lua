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

-- Differential check: for ASCII inputs, the emitted expression must accept exactly what Lua accepts. The
-- reference is a small independent backtracking matcher over the ECMA subset we emit (no regex library in Lua).
local function ecma_matches(re, subject)
  -- parse into items
  local pos = 1
  local function parse_seq(stop_at_paren)
    local seq = {}
    while pos <= #re do
      local c = re:sub(pos, pos)
      if c == ")" then
        if stop_at_paren then return seq end
        error("unbalanced")
      end
      local item
      if c == "^" then item = { t = "bol" }; pos = pos + 1
      elseif c == "$" then item = { t = "eol" }; pos = pos + 1
      elseif c == "(" then
        pos = pos + 1
        local inner = parse_seq(true)
        pos = pos + 1
        item = { t = "group", seq = inner }
      elseif c == "[" then
        local neg = re:sub(pos + 1, pos + 1) == "^"
        pos = pos + (neg and 2 or 1)
        local ranges = {}
        local function atom()
          local ch = re:sub(pos, pos)
          if ch == "\\" then
            local n = re:sub(pos + 1, pos + 1)
            if n == "x" then
              local v = tonumber(re:sub(pos + 2, pos + 3), 16); pos = pos + 4; return v
            end
            pos = pos + 2
            return ({ t = 9, n = 10, f = 12, r = 13 })[n] or n:byte()
          end
          pos = pos + 1
          return ch:byte()
        end
        while re:sub(pos, pos) ~= "]" do
          local lo = atom()
          if re:sub(pos, pos) == "-" and re:sub(pos + 1, pos + 1) ~= "]" then
            pos = pos + 1
            ranges[#ranges + 1] = { lo, atom() }
          else
            ranges[#ranges + 1] = { lo, lo }
          end
        end
        pos = pos + 1
        item = { t = "set", neg = neg, ranges = ranges }
      elseif c == "\\" then
        local n = re:sub(pos + 1, pos + 1)
        if n == "s" or n == "S" then error("unexpected") end
        pos = pos + 2
        item = { t = "set", neg = false, ranges = { { n:byte(), n:byte() } } }
      else
        pos = pos + 1
        item = { t = "set", neg = false, ranges = { { c:byte(), c:byte() } } }
      end
      local q = re:sub(pos, pos)
      if q == "*" or q == "+" or q == "?" then
        pos = pos + 1
        local lazy = false
        if re:sub(pos, pos) == "?" then lazy = true; pos = pos + 1 end
        item = { t = "rep", item = item, min = q == "+" and 1 or 0, max = q == "?" and 1 or math.huge, lazy = lazy }
      end
      seq[#seq + 1] = item
    end
    return seq
  end
  local ast = parse_seq(false)
  local function one(item, i)
    if item.t ~= "set" or i > #subject then return false end
    local b = subject:byte(i)
    local inside = false
    for _, r in ipairs(item.ranges) do if b >= r[1] and b <= r[2] then inside = true end end
    return inside ~= item.neg
  end
  local match_seq
  local function match_item(item, i, k)
    if item.t == "bol" then return i == 1 and k(i) end
    if item.t == "eol" then return i == #subject + 1 and k(i) end
    if item.t == "set" then return one(item, i) and k(i + 1) end
    if item.t == "group" then return match_seq(item.seq, 1, i, k) end
    if item.t == "rep" then
      local function try(count, at)
        local function more() return count < item.max and match_item(item.item, at, function(j) return j > at and try(count + 1, j) end) end
        if item.lazy then
          return (count >= item.min and k(at)) or more()
        end
        return more() or (count >= item.min and k(at))
      end
      return try(0, i)
    end
  end
  match_seq = function(seq, n, i, k)
    if n > #seq then return k(i) end
    return match_item(seq[n], i, function(j) return match_seq(seq, n + 1, j, k) end)
  end
  for start = 1, #subject + 1 do
    if match_seq(ast, 1, start, function() return true end) then return true end
  end
  return false
end

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
  self:assert_equal(nil, s.options.logger)
  self:assert_false(pcall(function() return s:to_json_schema() end))
  -- without a logger nothing is reported and declaration succeeds
  schema.string({ pattern = "%bxy" })
end

return T
