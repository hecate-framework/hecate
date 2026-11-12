local test = require("harness.test")
local affected = require("lib.affected")
local T = test.Case("AffectedTest")

local deps = { core = {}, json = { "core" }, http = { "json" }, router = { "core" } }

function T:test_reverse_dependencies()
  local r = affected.compute({ "packages/json/src/x.lua" }, deps)
  self:assert_equal("http,json", table.concat(r, ","))
end
function T:test_tooling_change_affects_all()
  self:assert_equal(4, #affected.compute({ "tools/run.lua" }, deps))
end
function T:test_docs_only_affects_none()
  self:assert_equal(0, #affected.compute({ "docs/roadmap.md", "README.md" }, deps))
end
function T:test_an_example_change_affects_the_kernel_it_runs_on()
  -- The examples are applications of the kernel; CI runs them in the run of `kernel` (ci.yml).
  local graph = { core = {}, kernel = { "core" }, app = { "kernel" } }
  self:assert_equal("app,kernel", table.concat(affected.compute({ "examples/hello/src/hello/init.lua" }, graph), ","))
  self:assert_equal("app,kernel", table.concat(affected.compute({ "examples/hello/tests/hello_test.lua" }, graph), ","))
end
function T:test_an_example_readme_affects_none()
  local graph = { core = {}, kernel = { "core" } }
  self:assert_equal(0, #affected.compute({ "examples/hello/README.md", "examples/README.md" }, graph))
end
function T:test_needs_follows_dependencies_transitively()
  local graph = { core = {}, json = { "core" }, http = { "json" }, router = { "core" }, app = { "http", "router" } }
  self:assert_true(affected.needs({ "json" }, "json", graph))
  self:assert_true(affected.needs({ "http" }, "json", graph))
  self:assert_true(affected.needs({ "router", "app" }, "json", graph))
  self:assert_false(affected.needs({ "router", "core" }, "json", graph))
  self:assert_false(affected.needs({}, "json", graph))
  self:assert_false(affected.needs({ "unknown" }, "json", graph))
end
return T
