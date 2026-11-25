---@diagnostic disable: need-check-nil, param-type-mismatch
local test = require("harness.test")
local util = require("lib.util")
local package_kind = require("lib.package_kind")
local affected = require("lib.affected")
local T = test.Case("PackageKindTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local ROCK_README = "# `hecate-core`\n\n> Things.\n\n| | |\n|---|---|\n| Rock | `hecate-core` |\n| Repository | read-only mirror `hecate-framework/hecate-core`, generated from this directory (ADR 0017) |\n"
local ACTIONS_README = "# `hecate-actions`\n\n> Actions.\n\n| | |\n|---|---|\n| Rock | none |\n| Kind | actions |\n| Repository | read-only mirror `hecate-framework/hecate-actions`, generated from this directory (ADR 0017) |\n"

function T:set_up()
  self.root = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "package-kind-test"))
  util.mkdir(self.root .. "/packages")
  util.mkdir(self.root .. "/.claude")
  util.mkdir(self.root .. "/.claude/agents")
end

function T:tear_down() util.remove_tree(self.root) end

--- A scratch package directory with a README and a CLAUDE.md.
function T:package(name, readme)
  util.mkdir(self.root .. "/packages/" .. name)
  write(self.root .. "/packages/" .. name .. "/README.md", readme)
  write(self.root .. "/packages/" .. name .. "/CLAUDE.md", "# x\n")
  write(self.root .. "/.claude/agents/pkg-" .. name .. ".md", "x\n")
end

function T:test_the_kind_is_read_from_the_readme_and_defaults_to_rock()
  self:assert_equal("rock", package_kind.of(ROCK_README))
  self:assert_equal("rock", package_kind.of(nil))
  self:assert_equal("actions", package_kind.of(ACTIONS_README))
  self:assert_equal("actions", package_kind.of("\n| Kind | `actions` |\n"))
  self:assert_true(package_kind.known(ACTIONS_README))
  self:assert_false(package_kind.known("\n| Kind | plugin |\n"))
end

function T:test_rocks_lists_only_the_packages_that_are_rocks()
  self:package("core", ROCK_README)
  self:package("actions", ACTIONS_README)
  self:assert_equal("core", table.concat(package_kind.rocks(self.root), ","))
end

function T:test_the_dependency_graph_has_no_node_for_a_package_without_lua()
  self:package("core", ROCK_README)
  write(self.root .. "/packages/core/hecate-core-scm-1.rockspec", 'dependencies = {\n  "lua >= 5.5, < 5.6",\n}\n')
  self:package("actions", ACTIONS_README)
  local graph = require("lib.deps").graph(self.root)
  self:assert_true(graph.core ~= nil)
  self:assert_equal(nil, graph.actions)
end

function T:test_a_change_to_the_actions_affects_no_rock()
  local graph = { core = {}, cli = { "core" } }
  self:assert_equal(0, #affected.compute({ "packages/actions/setup/action.yml" }, graph))
end

function T:test_check_package_structure_accepts_a_package_of_kind_actions()
  self:package("actions", ACTIONS_README)
  util.mkdir(self.root .. "/packages/actions/setup")
  write(self.root .. "/packages/actions/setup/action.yml", "name: x\n")
  local report = require("tasks.check_package_structure").run({ root = self.root, args = {} })
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
end

function T:test_check_package_structure_still_checks_the_files_of_that_package()
  self:package("actions", ACTIONS_README)
  os.remove(self.root .. "/packages/actions/CLAUDE.md")
  os.remove(self.root .. "/.claude/agents/pkg-actions.md")
  local report = require("tasks.check_package_structure").run({ root = self.root, args = {} })
  self:assert_false(report.ok)
  local text = table.concat(report.problems, "\n")
  self:assert_true(text:find("missing packages/actions/CLAUDE.md", 1, true) ~= nil, text)
  self:assert_true(text:find("missing .claude/agents/pkg-actions.md", 1, true) ~= nil, text)
  self:assert_true(text:find("no <directory>/action.yml", 1, true) ~= nil, text)
end

function T:test_check_package_structure_refuses_a_rockspec_and_a_wrong_mirror_in_that_package()
  self:package("actions", (ACTIONS_README:gsub("hecate%-framework/hecate%-actions", "hecate-framework/hecate-setup")))
  util.mkdir(self.root .. "/packages/actions/setup")
  write(self.root .. "/packages/actions/setup/action.yml", "name: x\n")
  write(self.root .. "/packages/actions/hecate-actions-scm-1.rockspec", "")
  local report = require("tasks.check_package_structure").run({ root = self.root, args = {} })
  local text = table.concat(report.problems, "\n")
  self:assert_true(text:find("has no rockspec", 1, true) ~= nil, text)
  self:assert_true(text:find("must name the mirror hecate-framework/hecate-actions", 1, true) ~= nil, text)
end

function T:test_a_rock_still_needs_its_rockspec_and_tests()
  self:package("core", ROCK_README)
  local report = require("tasks.check_package_structure").run({ root = self.root, args = {} })
  local text = table.concat(report.problems, "\n")
  self:assert_true(text:find("hecate-core-scm-1.rockspec", 1, true) ~= nil, text)
  self:assert_true(text:find("packages/core/tests", 1, true) ~= nil, text)
end

function T:test_the_catalogue_row_of_a_package_without_a_rock()
  local catalogue = require("lib.catalogue")
  local meta = catalogue.parse_readme(ACTIONS_README .. "| Layer | none |\n| Roadmap phase | 3 |\n| Status | alpha |\n")
  self:assert_equal("actions", meta.kind)
  local row = catalogue.render({ { name = "actions", meta = meta } })
  self:assert_true(row:find("| [`actions`](actions) | none |", 1, true) ~= nil, row)
end

function T:test_the_real_actions_package_is_declared_as_actions()
  local f = assert(io.open(ROOT .. "/packages/actions/README.md", "rb"))
  local text = f:read("a")
  f:close()
  self:assert_equal("actions", package_kind.of(text))
  self:assert_true(util.exists(ROOT .. "/packages/actions/setup/action.yml"))
  self:assert_false(util.exists(ROOT .. "/actions"))
end

return T
