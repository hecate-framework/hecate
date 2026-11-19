-- The documentation site of the example builds: `docs/` goes through
-- `generate_project_documentation` (real file system, native module of
-- `doc`) with no problem, the expected files exist, and two builds are
-- byte-identical. Without the native module the tests are skipped locally;
-- CI sets HECATE_REQUIRE_DOC_NATIVE=1 when `doc` is affected: they fail.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields
---@diagnostic disable: undefined-field, inject-field
local test = require("harness.test")
local uv = require("luv")
local T = test.Case("HelloDocsBuildTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
here = here:gsub("\\", "/")

local available, doc = pcall(require, "hecate.doc")
local reactor = available and require("hecate.reactor") or nil
if not available and os.getenv("HECATE_REQUIRE_DOC_NATIVE") == "1" then
  error("the documentation of the example cannot be built: " .. tostring(doc), 0)
end

--- Builds the site into `output_dir` and returns the report.
local function build(output_dir)
  local file_system = doc.SystemFileSystem()
  return doc.generate_project_documentation({
    project_dir = here,
    output_dir = output_dir,
    clean_output_dir = true,
    fail_on_problems = true,
    file_system = file_system,
  })
end

--- Every file below `directory`: relative path (sorted) -> contents.
local function snapshot(directory)
  local file_system = doc.SystemFileSystem()
  local files = {}
  local function walk(relative)
    for _, entry in ipairs(file_system:list(directory .. relative) or {}) do
      local path = relative .. "/" .. entry.name
      if entry.is_directory then walk(path) else files[path:sub(2)] = file_system:read(directory .. path) end
    end
  end
  walk("")
  return files
end

--- Runs `body(first, second)` in a reactor (the file system suspends) with
--- two fresh temporary directories, removed afterwards.
local function with_two_directories(body)
  local base = uv.os_tmpdir():gsub("\\", "/")
  local first = assert(uv.fs_mkdtemp(base .. "/hecate-hello-docs-XXXXXX")):gsub("\\", "/")
  local second = assert(uv.fs_mkdtemp(base .. "/hecate-hello-docs-XXXXXX")):gsub("\\", "/")
  local ok, err = pcall(reactor.run, function()
    local ran, failure = pcall(body, first .. "/site", second .. "/site")
    local file_system = doc.SystemFileSystem()
    file_system:remove_tree(first)
    file_system:remove_tree(second)
    if not ran then error(failure, 0) end
  end)
  uv.fs_rmdir(first)
  uv.fs_rmdir(second)
  if not ok then error(err, 0) end
end

function T:test_the_site_builds_without_problem_and_holds_the_expected_files()
  if not available then return end
  with_two_directories(function(out)
    local report = build(out)
    self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
    local files = snapshot(out)
    for _, path in ipairs({ "index.html", "en/index.html", "en/guide/index.html", "en/guide/endpoints/index.html",
      "en/guide/request-flow/index.html", "logo.svg", "logo-dark.svg", "favicon.svg", "favicon-dark.svg",
      "hello-theme.css", "llms.txt", "llms-full.txt", "404.html" }) do
      self:assert_not_nil(files[path], "missing " .. path)
    end
    self:assert_not_nil(files["en/index.html"]:find("hello-theme.css", 1, true), "the page links the CSS file")
    self:assert_not_nil(files["llms.txt"]:find("hello", 1, true))
  end)
end

function T:test_two_builds_are_byte_identical()
  if not available then return end
  with_two_directories(function(first, second)
    self:assert_equal(0, #build(first).problems)
    self:assert_equal(0, #build(second).problems)
    local a, b = snapshot(first), snapshot(second)
    for path, data in pairs(a) do
      self:assert_not_nil(b[path], "only in the first build: " .. path)
      self:assert_true(b[path] == data, "differs between the builds: " .. path)
    end
    for path in pairs(b) do self:assert_not_nil(a[path], "only in the second build: " .. path) end
  end)
end

return T
