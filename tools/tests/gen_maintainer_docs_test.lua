---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local task = require("tasks.gen_maintainer_docs")
local util = require("lib.util")
local T = test.Case("GenMaintainerDocsTaskTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")
local OUT = "website/maintainer/en"

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

function T:set_up()
  self.root = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "gen-maintainer-docs-test"))
  util.mkdir(self.root .. "/docs")
  util.mkdir(self.root .. "/docs/architecture")
  util.mkdir(self.root .. "/docs/adr")
  write(self.root .. "/docs/architecture/b.md", "# B spec\n\nSecond.\n")
  write(self.root .. "/docs/architecture/a.md", "# A spec\n\nFirst, see [b](b.md) and [adr](../adr/0001-x.md).\n")
  write(self.root .. "/docs/architecture/README.md", "# Not a page\n")
  write(self.root .. "/docs/adr/README.md", "# Architecture Decision Records\n\nIndex.\n\n- [x](0001-x.md)\n")
  write(self.root .. "/docs/adr/0001-x.md", "# 0001 — X\n\n- **Status:** Accepted\n")
end
function T:tear_down() util.remove_tree(self.root) end

function T:run(...) return task.run({ root = self.root, args = { ... } }) end
function T:page(path) return read(("%s/%s/%s"):format(self.root, OUT, path)) end

function T:test_a_run_writes_the_pages_and_the_architecture_index_and_the_adr_readme_is_the_adr_index()
  local result = self:run()
  self:assert_true(result.ok, table.concat(result.problems, "\n"))
  self:assert_true(self:page("architecture/a.md"):find("[b](b.md)", 1, true) ~= nil)
  self:assert_true(self:page("adr/0001-x.md") ~= nil)
  local index = self:page("architecture/index.md")
  self:assert_true(index:find("- [A spec](a.md)\n- [B spec](b.md)", 1, true) ~= nil, index)
  self:assert_true(index:find("Not a page", 1, true) == nil)
  self:assert_true(self:page("adr/index.md"):find("# Architecture Decision Records", 1, true) ~= nil)
end

function T:test_a_second_run_changes_nothing_and_check_passes()
  self:run()
  local again = self:run()
  self:assert_true(again.output:find("0 written", 1, true) ~= nil, again.output)
  self:assert_true(self:run("--check").ok)
end

function T:test_check_writes_nothing_and_fails_on_a_stale_page()
  local before = self:run("--check")
  self:assert_true(before.ok)
  self:assert_nil(self:page("architecture/a.md"))
  self:run()
  write(self.root .. "/docs/architecture/b.md", "# B spec\n\nChanged.\n")
  local stale = self:run("--check")
  self:assert_false(stale.ok)
  self:assert_true(stale.problems[1]:find("out of date", 1, true) ~= nil, stale.problems[1])
end

function T:test_a_page_without_the_marker_is_never_overwritten()
  util.mkdir(self.root .. "/" .. OUT)
  util.mkdir(self.root .. "/" .. OUT .. "/architecture")
  write(self.root .. "/" .. OUT .. "/architecture/a.md", "hand written\n")
  local result = self:run()
  self:assert_false(result.ok)
  self:assert_equal("hand written\n", self:page("architecture/a.md"))
end

function T:test_an_unknown_argument_is_a_usage_error()
  local result = self:run("--nope")
  self:assert_false(result.ok)
  self:assert_true(result.problems[1]:find("usage: gen-maintainer-docs", 1, true) ~= nil)
end

return T
