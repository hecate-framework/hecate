---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local task = require("tasks.fetch_fixtures")
local sha256 = require("lib.sha256")
local util = require("lib.util")
local T = test.Case("FetchFixturesTaskTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")
local COMMIT = ("0123456789abcdef"):rep(2) .. "01234567"

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
  self.root = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "fetch-fixtures-test"))
  util.mkdir(self.root .. "/packages/demo/tests")
  self.downloads, self.pauses, self.git_calls = {}, 0, {}
  self.content = "content"
  self.fail = false
end

function T:tear_down() util.remove_tree(self.root) end

function T:declare(entries)
  local lines = { "return {" }
  for _, entry in ipairs(entries) do
    local fields = {}
    for key, value in pairs(entry) do fields[#fields + 1] = ("%s = %q"):format(key, value) end
    table.sort(fields)
    lines[#lines + 1] = "  { " .. table.concat(fields, ", ") .. " },"
  end
  lines[#lines + 1] = "}"
  write(self.root .. "/packages/demo/tests/external.lua", table.concat(lines, "\n") .. "\n")
end

function T:run()
  return task.run({
    root = self.root,
    args = { "demo" },
    download = function(url, path, max)
      self.downloads[#self.downloads + 1] = { url = url, max = max }
      if self.fail then return "unreachable", false end
      write(path, self.content)
      return "", true
    end,
    pause = function() self.pauses = self.pauses + 1 end,
    git = function(dir, args)
      self.git_calls[#self.git_calls + 1] = args
      return "", true
    end,
  })
end

function T:test_a_package_without_a_declaration_succeeds_and_downloads_nothing()
  local report = task.run({ root = self.root, args = { "absent" } })
  self:assert_true(report.ok)
  self:assert_equal(0, #report.problems)
end

function T:test_a_file_entry_is_fetched_then_cached()
  self:declare({ { name = "a.txt", url = "https://example.org/a.txt", sha256 = sha256.hex("content") } })
  local first = self:run()
  self:assert_true(first.ok, table.concat(first.problems, "; "))
  self:assert_equal("fetched", first.data.entries[1].state)
  self:assert_equal("file", first.data.entries[1].kind)
  self:assert_equal("content", read(self.root .. "/.hecate/fixtures/demo/a.txt"))
  self:assert_equal(16 * 1024 * 1024, self.downloads[1].max, "the documented default limit")
  local second = self:run()
  self:assert_equal("cached", second.data.entries[1].state)
  self:assert_equal(1, #self.downloads)
end

function T:test_an_entry_without_a_kind_is_reported_and_gives_no_download_call()
  self:declare({ { name = "a.txt", url = "https://example.org/a.txt" }, { name = "b" }, { name = "c", repository = "https://x/r" },
    { name = "d", url = "https://example.org/d", sha256 = sha256.hex("x"), repository = "https://x/r", commit = COMMIT } })
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(4, #report.problems)
  for _, problem in ipairs(report.problems) do
    self:assert_true(problem:find("repository and commit, or url and sha256", 1, true) ~= nil, problem)
  end
  self:assert_equal(0, #self.downloads)
  self:assert_equal(0, #self.git_calls)
  for _, entry in ipairs(report.data.entries) do
    self:assert_equal("none", entry.kind)
    self:assert_equal("failed", entry.state)
  end
end

function T:test_a_bad_shape_gives_no_download_and_no_git_call()
  self:declare({
    { name = "a.txt", url = "http://example.org/a.txt", sha256 = sha256.hex("content") },
    { name = "b.txt", url = "https://example.org/b b.txt", sha256 = sha256.hex("content") },
    { name = "c.txt", url = "https://example.org/c.txt", sha256 = "abc" },
    { name = "../d.txt", url = "https://example.org/d.txt", sha256 = sha256.hex("content") },
    { name = "e", repository = "https://example.org/e", commit = "main" },
    { name = "f", repository = "https://example.org/f", commit = COMMIT .. "; touch pwned" },
  })
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(6, #report.problems)
  self:assert_equal(0, #self.downloads)
  self:assert_equal(0, #self.git_calls)
  for _, entry in ipairs(report.data.entries) do self:assert_equal("failed", entry.state, entry.name) end
  self:assert_false(util.exists(self.root .. "/.hecate/fixtures/demo/e"), "no directory for a refused git entry")
end

function T:test_the_json_report_lists_the_failed_state()
  self:declare({ { name = "a.txt", url = "http://example.org/a.txt", sha256 = sha256.hex("content") } })
  local report = self:run()
  local json = util.json({ task = "fetch-fixtures", ok = report.ok, problems = report.problems, data = report.data })
  self:assert_true(json:find('"state":"failed"', 1, true) ~= nil, json)
  self:assert_true(json:find('"ok":false', 1, true) ~= nil, json)
  self:assert_true(json:find('"package":"demo"', 1, true) ~= nil, json)
end

function T:test_a_failed_download_is_tried_three_times_and_reported()
  self:declare({ { name = "a.txt", url = "https://example.org/a.txt", sha256 = sha256.hex("content") } })
  util.mkdir(self.root .. "/.hecate/fixtures/demo")
  write(self.root .. "/.hecate/fixtures/demo/a.txt", "stale")
  self.fail = true
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(3, #self.downloads)
  self:assert_equal(2, self.pauses)
  self:assert_equal("failed", report.data.entries[1].state)
  self:assert_true(report.problems[1]:find("unreachable", 1, true) ~= nil)
  self:assert_nil(read(self.root .. "/.hecate/fixtures/demo/a.txt"), "the stale file is deleted")
end

function T:test_a_mismatching_or_empty_download_is_refused()
  self:declare({ { name = "a.txt", url = "https://example.org/a.txt", sha256 = sha256.hex("content") } })
  self.content = "tampered"
  local mismatch = self:run()
  self:assert_false(mismatch.ok)
  self:assert_true(mismatch.problems[1]:find("sha256", 1, true) ~= nil)
  self:assert_nil(read(self.root .. "/.hecate/fixtures/demo/a.txt"))
  self.content = ""
  local empty = self:run()
  self:assert_false(empty.ok)
  self:assert_true(empty.problems[1]:find("empty", 1, true) ~= nil)
end

function T:test_an_entry_can_lower_its_limit()
  self:declare({ { name = "a.txt", url = "https://example.org/a.txt", sha256 = sha256.hex("content") } })
  write(self.root .. "/packages/demo/tests/external.lua",
    ('return { { name = "a.txt", url = "https://example.org/a.txt", sha256 = %q, max_bytes = 3 } }\n'):format(sha256.hex("content")))
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(3, self.downloads[1].max)
  self:assert_true(report.problems[1]:find("larger than 3 bytes", 1, true) ~= nil, report.problems[1])
end

function T:test_a_git_entry_quotes_the_repository_and_the_commit()
  self:declare({ { name = "r", repository = "https://example.org/r.git", commit = COMMIT, path = "x" } })
  local report = self:run()
  self:assert_true(report.ok, table.concat(report.problems, "; "))
  self:assert_equal("git", report.data.entries[1].state)
  local fetch
  for _, args in ipairs(self.git_calls) do
    if args:find("^fetch") then fetch = args end
  end
  self:assert_not_nil(fetch)
  local quote = util.is_windows() and '"' or "'"
  self:assert_true(fetch:find(quote .. COMMIT .. quote, 1, true) ~= nil, "the commit is quoted: " .. fetch)
  self:assert_true(fetch:find(quote .. "https://example.org/r.git" .. quote, 1, true) ~= nil, fetch)
end

return T
