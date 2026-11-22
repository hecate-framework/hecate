-- Path strings as pure functions: the rules of Windows are tested here on every platform.
local test = require("harness.test")
local paths = require("hecate.doc.internal.paths")
local T = test.Case("PathsTest")

function T:test_separators_become_slashes()
  self:assert_equal("C:/docs/en/a.md", paths.separators("C:\\docs\\en/a.md"))
  self:assert_equal("//server/share/x", paths.separators("\\\\server\\share\\x"))
end

function T:test_absolute_paths_start_with_a_separator_or_a_drive_and_a_separator()
  for _, path in ipairs({ "/a", "\\a", "\\\\server\\share", "C:/a", "C:\\a", "c:/", "z:\\" }) do
    self:assert_true(paths.is_absolute(path), path)
  end
  for _, path in ipairs({ "a", "./a", "C:a", "C:", "v:1", "", "a/b", "docs\\en" }) do
    self:assert_false(paths.is_absolute(path), path)
  end
end

function T:test_a_drive_relative_path_is_refused_only_where_the_rule_applies()
  for _, path in ipairs({ "C:a", "C:", "d:docs/x" }) do
    self:assert_true(paths.is_drive_relative(path, true), path)
    self:assert_false(paths.is_drive_relative(path, false), path .. " is a plain name off Windows")
  end
  for _, path in ipairs({ "C:/a", "C:\\a", "a", "/a" }) do self:assert_false(paths.is_drive_relative(path, true), path) end
  self:assert_equal(paths.is_windows(), paths.is_drive_relative("v:1"), "v:1 follows the running platform")
end

function T:test_normalise_folds_dots_and_separators()
  local cases = {
    { "docs//en/./a/../b/", "docs/en/b" }, { "./docs", "docs" }, { ".", "." }, { "", "." }, { "a/..", "." },
    { "../a", "../a" }, { "a/../..", ".." }, { "/a/../..", "/" }, { "C:\\docs\\..\\x", "C:/x" },
    { "//server/share/a/../b", "//server/share/b" }, { "/", "/" },
  }
  for _, case in ipairs(cases) do self:assert_equal(case[2], paths.normalise(case[1]), case[1]) end
end

function T:test_roots_are_recognised()
  for _, path in ipairs({ "/", "//", "C:/", "C:\\", "c:", "\\\\server", "//server/share", "//server/share/", "/a/..", "/." }) do
    -- `c:` alone is not a root of the normal form (it is drive relative): it is refused by the option check instead.
    if path ~= "c:" then self:assert_true(paths.is_root(path), path) end
  end
  for _, path in ipairs({ "/a", "C:/a", "//server/share/a", "a", ".", "..", "~" }) do self:assert_false(paths.is_root(path), path) end
end

function T:test_resolve_keeps_an_absolute_path_and_the_current_directory_adds_nothing()
  self:assert_equal("acme/docs", paths.resolve("acme", "docs"))
  self:assert_equal("acme/docs", paths.resolve("acme/", "docs"))
  self:assert_equal("docs", paths.resolve(".", "docs"))
  self:assert_equal("/abs", paths.resolve("acme", "/abs"))
  self:assert_equal("C:\\abs", paths.resolve("acme", "C:\\abs"))
  self:assert_equal("v:1", paths.resolve(".", "v:1"))
end

function T:test_relation_compares_normal_forms_case_folded()
  self:assert_equal("same", paths.relation("docs", "./docs/"))
  self:assert_equal("same", paths.relation("Docs", "docs"))
  self:assert_equal("inside", paths.relation("docs/dist", "docs"))
  self:assert_equal("contains", paths.relation("docs", "docs/en"))
  self:assert_equal("contains", paths.relation(".", "docs"))
  self:assert_equal("contains", paths.relation("..", "docs"))
  self:assert_equal("contains", paths.relation("../..", "../docs"))
  self:assert_equal("inside", paths.relation("docs", ".."))
  self:assert_equal("same", paths.relation("C:\\a\\b", "c:/A/b"))
  self:assert_nil(paths.relation("docs", "dist"))
  self:assert_nil(paths.relation("docsx", "docs"))
  self:assert_nil(paths.relation("/a", "a"), "an absolute and a relative path are not comparable")
  self:assert_nil(paths.relation("C:/a", "D:/a"))
  self:assert_nil(paths.relation("../x", "y"))
end

function T:test_below_returns_the_segments_under_a_base()
  self:assert_equal("a,b", table.concat(paths.below("docs", "docs/a/b") or {}, ","))
  self:assert_equal("", table.concat(paths.below("docs", "docs") or {}, ","))
  self:assert_nil(paths.below("docs", "other/a"))
  self:assert_nil(paths.below("docs/a", "docs"))
end

return T
