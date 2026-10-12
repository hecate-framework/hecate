local test = require("harness.test")
local depgraph = require("lib.depgraph")
local T = test.Case("DepgraphTest")

function T:test_transitive_reduction()
  local r = depgraph.reduce({ a = { "b", "c" }, b = { "c" }, c = {} })
  self:assert_equal("b", table.concat(r.a, ","))
end
function T:test_render()
  local out = depgraph.render({ a = { "b" }, b = {} }, { { id = "G", title = "Group", members = { "b", "a" } } })
  self:assert_true(out:find("a --> b", 1, true) ~= nil)
  self:assert_true(out:find("subgraph G[Group]", 1, true) ~= nil)
end
return T
