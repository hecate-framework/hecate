local test = require("harness.test")
local changes = require("lib.changes")
local T = test.Case("ChangesTest")

function T:test_documentation_files_are_not_code()
  for _, path in ipairs({ "README.md", "docs/adr/0001.md", "docs/x.png", "website/en/a.html", ".claude/agents/x.md",
    "HANDOFF.md", "packages/core/README.md", ".github/ISSUE_TEMPLATE/bug.yml", "CHANGELOG.md" }) do
    self:assert_true(changes.is_documentation(path), path)
  end
end

function T:test_anything_else_is_code()
  for _, path in ipairs({ "packages/core/src/hecate/core.lua", "tools/run.lua", ".github/workflows/ci.yml",
    ".github/dependabot.yml", "docs.lua", "VERSION", "examples/hello/main.lua", "packages/x/native/Cargo.lock" }) do
    self:assert_false(changes.is_documentation(path), path)
  end
end

function T:test_a_diff_is_code_when_one_file_is_code_or_when_it_is_empty()
  self:assert_false(changes.code_changed({ "docs/a.md", "README.md" }))
  self:assert_true(changes.code_changed({ "docs/a.md", "tools/run.lua" }))
  self:assert_true(changes.code_changed({}))
end

return T
