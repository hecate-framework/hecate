---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local fixtures = require("lib.fixtures")
local sha256 = require("lib.sha256")
local T = test.Case("FixturesTest")

local dir = (os.tmpname() .. "-fixtures"):gsub("\\", "/")
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
local function fake(content, ok)
  local calls = { n = 0 }
  return function(url, path)
    calls.n = calls.n + 1
    calls.url = url
    if ok == false then return "boom", false end
    write(path, content)
    return "", true
  end, calls
end

function T:test_the_kind_of_an_entry()
  self:assert_equal("file", fixtures.kind({ name = "a", url = "https://x/a", sha256 = "0" }))
  self:assert_equal("git", fixtures.kind({ name = "a", repository = "r", commit = "c" }))
  self:assert_nil(fixtures.kind({ name = "a", url = "https://x/a" }))
end

function T:test_the_shape_of_a_file_entry_is_checked()
  local good = { name = "a.txt", url = "https://x/a.txt", sha256 = ("0"):rep(64) }
  self:assert_equal(0, #fixtures.problems(good))
  self:assert_equal(1, #fixtures.problems({ name = "a.txt", url = "http://x/a.txt", sha256 = good.sha256 }))
  self:assert_equal(1, #fixtures.problems({ name = "a.txt", url = good.url, sha256 = ("A"):rep(64) }))
  self:assert_equal(1, #fixtures.problems({ name = "a.txt", url = good.url, sha256 = "abc" }))
  self:assert_equal(1, #fixtures.problems({ name = "../a", url = good.url, sha256 = good.sha256 }))
end

function T:test_a_download_that_matches_the_pin_is_kept_then_cached()
  local entry = { name = "a.txt", url = "https://x/a.txt", sha256 = sha256.hex("content") }
  local download, calls = fake("content")
  self:assert_equal("fetched", (fixtures.ensure(entry, dir .. "-ok", download)))
  self:assert_equal("content", read(dir .. "-ok/a.txt"))
  self:assert_equal("https://x/a.txt", calls.url)
  self:assert_equal("cached", (fixtures.ensure(entry, dir .. "-ok", download)))
  self:assert_equal(1, calls.n, "a matching file is not downloaded again")
  os.remove(dir .. "-ok/a.txt")
end

function T:test_a_download_that_does_not_match_is_refused_and_removed()
  local entry = { name = "b.txt", url = "https://x/b.txt", sha256 = sha256.hex("expected") }
  local state, problem = fixtures.ensure(entry, dir .. "-bad", (fake("tampered")))
  self:assert_nil(state)
  self:assert_true(problem:find("sha256", 1, true) ~= nil)
  self:assert_nil(read(dir .. "-bad/b.txt"))
  self:assert_nil(read(dir .. "-bad/b.txt.part"))
end

function T:test_a_stale_file_is_replaced_and_a_failed_download_reports()
  local entry = { name = "c.txt", url = "https://x/c.txt", sha256 = sha256.hex("new") }
  local first = fixtures.ensure({ name = "c.txt", url = entry.url, sha256 = sha256.hex("old") }, dir .. "-stale", (fake("old")))
  self:assert_equal("fetched", first)
  self:assert_equal("fetched", (fixtures.ensure(entry, dir .. "-stale", (fake("new")))))
  self:assert_equal("new", read(dir .. "-stale/c.txt"))
  local state, problem = fixtures.ensure({ name = "d.txt", url = entry.url, sha256 = entry.sha256 }, dir .. "-stale", (fake("", false)))
  self:assert_nil(state)
  self:assert_true(problem:find("boom", 1, true) ~= nil)
  os.remove(dir .. "-stale/c.txt")
end

return T
