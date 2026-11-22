local test = require("harness.test")
local core = require("hecate.core")
local constraint = require("hecate.cli.constraint")
local T = test.Case("CliConstraintTest")

function T:test_ordering_of_versions()
  local order = constraint.compare
  self:assert_equal(-1, order("0.9", "0.10"))
  self:assert_equal(-1, order("1.2.3", "1.10"))
  self:assert_equal(1, order("2.0", "1.99.99"))
  self:assert_equal(0, order("1.0", "1.0-3"))      -- a missing revision matches any revision
  self:assert_equal(-1, order("1.0-1", "1.0-2"))
  self:assert_equal(1, order("1.0-2", "1.0-1"))
  self:assert_equal(-1, order("1.0rc1", "1.0"))    -- pre-releases come before the release
  self:assert_equal(-1, order("1.0alpha", "1.0beta"))
  self:assert_equal(-1, order("1.0beta", "1.0rc1"))
  self:assert_equal(1, order("scm-1", "99.0"))     -- development versions come after every release
  self:assert_equal(1, order("dev-1", "scm-1"))
end

function T:test_pessimistic_operator()
  local function ok(version, text) return constraint.satisfies(version, text) end
  self:assert_true(ok("0.3.5-1", "~> 0.3"))
  self:assert_true(ok("0.3-1", "~> 0.3"))
  self:assert_false(ok("0.4.0-1", "~> 0.3"))
  self:assert_false(ok("0.2.9-1", "~> 0.3"))
  -- `~>` is a prefix match on the components, not the "at least, below the next" of other ecosystems.
  self:assert_true(ok("1.2.3.4", "~> 1.2.3"))
  self:assert_false(ok("1.2.9", "~> 1.2.3"))
  self:assert_false(ok("1.2.2", "~> 1.2.3"))
  self:assert_true(ok("2.7", "~> 2"))
end

function T:test_comparison_operators_and_lists()
  local function ok(version, text) return constraint.satisfies(version, text) end
  self:assert_true(ok("1.5", ">= 1.0, < 2.0"))
  self:assert_false(ok("2.0", ">= 1.0, < 2.0"))
  self:assert_true(ok("1.0", "1.0"))               -- no operator: an exact version
  self:assert_true(ok("1.0-4", "== 1.0"))
  self:assert_false(ok("1.0-4", "== 1.0-3"))
  self:assert_true(ok("1.1", "~= 1.0"))
  self:assert_true(ok("1.1", "!= 1.0"))
  self:assert_true(ok("1.0", "<= 1.0"))
  self:assert_false(ok("1.0", "> 1.0"))
  self:assert_true(ok("anything", ""))             -- no constraint: every version
end

function T:test_the_corners_of_luarocks_are_kept()
  -- Components are compared by position: 1.0 and 1.0.0 have different lengths, so they are not equal.
  self:assert_false(constraint.satisfies("1.0.0", "== 1.0"))
  self:assert_true(constraint.satisfies("1.0.0", ">= 1.0"))
end

function T:test_malformed_constraints_are_argument_errors_that_say_what_to_write()
  local function bad(text, fragment)
    local err = self:assert_error(function() constraint.parse(text) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find(fragment, 1, true) ~= nil)
  end
  bad("=> 1.0", "unknown constraint operator '=>'")
  bad("~~ 1.0", "unknown constraint operator")
  bad("~> ", "cannot read a version constraint")
  bad(">>", "cannot read a version constraint")
end

function T:test_agrees_with_luarocks_when_it_is_installed()
  local ok, vers = pcall(require, "luarocks.core.vers")
  if not ok then return end
  local samples = { "0.9", "0.10", "1.0", "1.0-1", "1.0-2", "1.0.0", "1.2.3", "1.10", "2.0rc1", "2.0", "scm-1", "dev-1", "1.0beta2", "3", "3.0-1" }
  for _, a in ipairs(samples) do
    for _, b in ipairs(samples) do
      local expected = vers.compare_versions(a, b) and 1 or (vers.compare_versions(b, a) and -1 or 0)
      self:assert_equal(expected, constraint.compare(a, b), a .. " vs " .. b)
    end
  end
  for _, text in ipairs({ "~> 0.3", ">= 1.0, < 2.0", "== 1.0", "~= 1.0", "> 1.0-1", "<= 2.0rc1" }) do
    local parsed = {}
    for _, c in ipairs(constraint.parse(text)) do parsed[#parsed + 1] = { op = c.op, version = vers.parse_version(c.text) } end
    for _, version in ipairs(samples) do
      self:assert_equal(vers.match_constraints(vers.parse_version(version), parsed), constraint.satisfies(version, text), version .. " " .. text)
    end
  end
end

return T
