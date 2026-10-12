local test = require("harness.test")
local b = require("lib.boundaries")
local T = test.Case("BoundariesTest")

function T:test_rank()
  self:assert_equal(1, b.rank("1 — Runtime"))
  self:assert_equal(4, b.rank("Data"))
  self:assert_equal(nil, b.rank("???"))
end
function T:test_rockspec_deps()
  local deps = b.rockspec_deps('dependencies = {\n  "lua >= 5.5",\n  "hecate-core",\n}\nbuild = {}')
  self:assert_equal(1, #deps)
  self:assert_equal("core", deps[1])
end
function T:test_required_packages()
  local r = b.required_packages('local a = require("hecate.core")\nlocal b = require "hecate.net.tcp"\n')
  self:assert_equal(2, #r)
  self:assert_equal("net", r[2])
end
function T:test_cycle()
  self:assert_equal(nil, b.find_cycle({ a = { "b" }, b = {} }))
  self:assert_equal(4, #b.find_cycle({ a = { "b" }, b = { "a" } }) + 1)
end
return T
