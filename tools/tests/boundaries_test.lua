local test = require("harness.test")
local b = require("lib.boundaries")
local T = test.Case("BoundariesTest")

function T:test_rank()
  self:assert_equal(1, b.rank("1 — Runtime"))
  self:assert_equal(4, b.rank("Data"))
  self:assert_equal(nil, b.rank("???"))
end
function T:test_rockspec_deps()
  local deps = b.rockspec_deps('\ndependencies = {\n  "lua >= 5.5",\n  "hecate-core",\n}\nbuild = {}')
  self:assert_equal(1, #deps)
  self:assert_equal("core", deps[1])
end
function T:test_required_packages()
  local r = b.required_packages('local a = require("hecate.core")\nlocal b = require "hecate.net.tcp"\n')
  self:assert_equal(2, #r)
  self:assert_equal("net", r[2])
end
function T:test_a_multi_word_package_name()
  self:assert_true(b.valid_name("core"))
  self:assert_true(b.valid_name("unicode-data"))
  self:assert_true(b.valid_name("a-b2-c"))
  for _, bad in ipairs({ "", "Core", "unicode_data", "a--b", "a-", "-a", "1a", "a b" }) do self:assert_false(b.valid_name(bad), bad) end
  self:assert_equal("unicode_data", b.module_name("unicode-data"))
  self:assert_equal("core", b.module_name("core"))
end
function T:test_a_multi_word_package_in_dependencies_and_requires()
  local deps = b.rockspec_deps('\ndependencies = {\n  "lua >= 5.5",\n  "hecate-unicode-data >= 18.0.0",\n  "hecate-core",\n}\n')
  self:assert_equal("unicode-data", deps[1])
  self:assert_equal("core", deps[2])
  local r = b.required_packages('local d = require("hecate.unicode_data")\nlocal e = require "hecate.unicode_data.decomposition"')
  self:assert_equal("unicode-data", r[1])
  self:assert_equal("unicode-data", r[2])
end
function T:test_cycle()
  self:assert_equal(nil, b.find_cycle({ a = { "b" }, b = {} }))
  self:assert_equal(4, #b.find_cycle({ a = { "b" }, b = { "a" } }) + 1)
end
return T
