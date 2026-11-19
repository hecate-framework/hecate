---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local fixtures = require("lib.fixtures")
local sha256 = require("lib.sha256")
local util = require("lib.util")
local T = test.Case("FixturesTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")

-- A directory of its own per test, under .hecate/ (git-ignored), removed afterwards.
function T:set_up()
  self.dir = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "fixtures-test"))
end

function T:tear_down() util.remove_tree(self.dir) end

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
  return function(url, path, max)
    calls.n = calls.n + 1
    calls.url = url
    calls.max = max
    if ok == false then return "boom", false end
    write(path, content)
    return "", true
  end, calls
end

local GOOD = { name = "a.txt", url = "https://x/a.txt", sha256 = ("0"):rep(64) }
local function with(fields)
  local entry = {}
  for k, v in pairs(GOOD) do entry[k] = v end
  for k, v in pairs(fields) do entry[k] = v end
  return entry
end

function T:test_the_kind_of_an_entry()
  self:assert_equal("file", fixtures.kind({ name = "a", url = "https://x/a", sha256 = "0" }))
  self:assert_equal("git", fixtures.kind({ name = "a", repository = "r", commit = "c" }))
  self:assert_nil(fixtures.kind({ name = "a", url = "https://x/a" }))
  self:assert_nil(fixtures.kind({ name = "a", repository = "r" }))
  self:assert_nil(fixtures.kind({ name = "a", url = "https://x/a", sha256 = "0", repository = "r", commit = "c" }),
    "an entry that is both a file and a repository is ambiguous")
end

function T:test_the_shape_of_a_file_entry_is_checked()
  self:assert_equal(0, #fixtures.problems(GOOD))
  self:assert_equal(1, #fixtures.problems(with({ url = "http://x/a.txt" })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("A"):rep(64) })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = "abc" })))
  self:assert_equal(1, #fixtures.problems(with({ name = "../a" })))
end

function T:test_the_sha256_must_be_exactly_64_lowercase_hexadecimal_digits()
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(63) })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(65) })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(63) .. "g" })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(63) .. " " })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(63) .. "\n" })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = ("0"):rep(32) .. ("F"):rep(32) })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = 0 })))
  self:assert_equal(1, #fixtures.problems(with({ sha256 = true })))
  self:assert_equal(0, #fixtures.problems(with({ sha256 = ("0123456789abcdef"):rep(4) })))
end

function T:test_the_name_must_be_a_plain_file_name()
  for _, name in ipairs({ "a/b", "a\\b", ".hidden", "", "/abs", "..", "a\nb" }) do
    self:assert_true(#fixtures.problems(with({ name = name })) >= 1, ("%q is not a file name"):format(name))
  end
  for _, name in ipairs({ 1, true, {} }) do
    self:assert_true(#fixtures.problems(with({ name = name })) >= 1, "a name is a string")
  end
  self:assert_equal(1, #fixtures.problems({ url = GOOD.url, sha256 = GOOD.sha256 }), "no name")
  self:assert_equal(0, #fixtures.problems(with({ name = "UnicodeData-1.0.txt" })))
end

function T:test_an_entry_that_is_both_a_file_and_a_repository_is_refused()
  local problems = fixtures.problems(with({ repository = "https://x/r", commit = ("a"):rep(40) }))
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("not both", 1, true) ~= nil)
  self:assert_equal(1, #fixtures.problems({ name = "a" }), "neither")
end

function T:test_a_url_that_cmd_or_the_shell_would_interpret_is_refused()
  for _, url in ipairs({
    "https://x/%PATH%", "https://x/a%20b", "https://x/a^b", 'https://x/a"b', "https://x/a'b", "https://x/a b",
    "https://x/a\nb", "https://x/a\rb", "https://x/a\tb", "https://x/a\0b", "https://x/a\"&calc&\"",
  }) do
    local problems = fixtures.problems(with({ url = url }))
    self:assert_equal(1, #problems, ("%q must be refused"):format(url))
    self:assert_true(problems[1]:find("url", 1, true) ~= nil)
    self:assert_not_nil(fixtures.url_problem(url))
  end
  self:assert_nil(fixtures.url_problem("https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt"))
  self:assert_not_nil(fixtures.url_problem("http://x/a"))
  self:assert_not_nil(fixtures.url_problem(nil))
  self:assert_not_nil(fixtures.url_problem(5))
end

function T:test_download_refuses_a_hostile_url_without_running_curl()
  local out, ok = fixtures.download('https://x/a"; touch pwned; "', self.dir .. "/x")
  self:assert_false(ok)
  self:assert_true(out:find("url", 1, true) ~= nil)
  self:assert_nil(read(self.dir .. "/x"))
  self:assert_false((select(2, fixtures.download("http://x/a", self.dir .. "/x"))))
end

function T:test_the_curl_command_is_limited_to_https_and_to_a_size()
  local real, command = util.capture, nil
  ---@diagnostic disable-next-line: duplicate-set-field
  util.capture = function(cmd) command = cmd return "", true end
  local ok = pcall(fixtures.download, "https://x/a.txt", self.dir .. "/a", 1234)
  pcall(fixtures.download, "https://x/b.txt", self.dir .. "/b")
  local default = command
  pcall(fixtures.download, "https://x/a.txt", self.dir .. "/a", 1234)
  util.capture = real
  self:assert_true(ok)
  self:assert_true(command:find("--proto '=https'", 1, true) ~= nil or command:find('--proto "=https"', 1, true) ~= nil, command)
  self:assert_true(command:find("--proto-redir", 1, true) ~= nil and command:find("=https", 1, true) ~= nil)
  self:assert_true(command:find("--max-filesize 1234 ", 1, true) ~= nil, command)
  self:assert_true(default:find(("--max-filesize %d "):format(fixtures.MAX_BYTES), 1, true) ~= nil, default)
  self:assert_true(command:find("--fail", 1, true) ~= nil and command:find("--max-time", 1, true) ~= nil)
end

local COMMIT =("0123456789abcdef"):rep(2) .. "01234567"

function T:test_the_shape_of_a_git_entry_is_checked()
  local good = { name = "r", repository = "https://github.com/a/b", commit = COMMIT, path = "x" }
  self:assert_equal(40, #COMMIT)
  self:assert_equal(0, #fixtures.problems(good))
  local function bad(fields)
    local entry = {}
    for k, v in pairs(good) do entry[k] = v end
    for k, v in pairs(fields) do entry[k] = v end
    return fixtures.problems(entry)
  end
  self:assert_equal(0, #bad({ commit = ("a"):rep(64) }), "a SHA-256 object name")
  self:assert_equal(1, #bad({ commit = ("a"):rep(39) }))
  self:assert_equal(1, #bad({ commit = ("a"):rep(41) }))
  self:assert_equal(1, #bad({ commit = ("a"):rep(63) }))
  self:assert_equal(1, #bad({ commit = "main" }))
  self:assert_equal(1, #bad({ commit = ("a"):rep(39) .. ";" }))
  self:assert_equal(1, #bad({ commit = ("a"):rep(39) .. " " }))
  self:assert_equal(1, #bad({ commit = "$(touch pwned)" .. ("a"):rep(26) }))
  self:assert_equal(1, #bad({ commit = 12 }))
  self:assert_equal(1, #bad({ repository = "http://github.com/a/b" }))
  self:assert_equal(1, #bad({ repository = "https://github.com/a/b c" }))
  self:assert_equal(1, #bad({ repository = "https://github.com/a/b'; touch pwned; '" }))
  self:assert_equal(1, #bad({ repository = "https://x/%PATH%" }))
  self:assert_equal(1, #bad({ name = "a/b" }))
  self:assert_equal(1, #bad({ name = ".git" }))
  self:assert_equal(1, #bad({ name = "" }))
  self:assert_equal(1, #bad({ name = "a\\b" }))
end

function T:test_max_bytes_is_a_positive_integer()
  self:assert_equal(0, #fixtures.problems(with({ max_bytes = 100 })))
  self:assert_equal(1, #fixtures.problems(with({ max_bytes = 0 })))
  self:assert_equal(1, #fixtures.problems(with({ max_bytes = -1 })))
  self:assert_equal(1, #fixtures.problems(with({ max_bytes = 1.5 })))
  self:assert_equal(1, #fixtures.problems(with({ max_bytes = "100" })))
end

function T:test_a_download_that_matches_the_pin_is_kept_then_cached()
  local entry = { name = "a.txt", url = "https://x/a.txt", sha256 = sha256.hex("content") }
  local download, calls = fake("content")
  self:assert_equal("fetched", (fixtures.ensure(entry, self.dir, download)))
  self:assert_equal("content", read(self.dir .. "/a.txt"))
  self:assert_equal("https://x/a.txt", calls.url)
  self:assert_equal(fixtures.MAX_BYTES, calls.max, "the documented default limit is passed to the download")
  self:assert_equal("cached", (fixtures.ensure(entry, self.dir, download)))
  self:assert_equal(1, calls.n, "a matching file is not downloaded again")
  self:assert_nil(read(self.dir .. "/a.txt.part"))
end

function T:test_an_entry_can_set_its_own_limit()
  local entry = { name = "a.txt", url = "https://x/a.txt", sha256 = sha256.hex("content"), max_bytes = 100 }
  local download, calls = fake("content")
  self:assert_equal("fetched", (fixtures.ensure(entry, self.dir, download)))
  self:assert_equal(100, calls.max)
end

function T:test_a_download_that_does_not_match_is_refused_and_removed()
  local entry = { name = "b.txt", url = "https://x/b.txt", sha256 = sha256.hex("expected") }
  local state, problem = fixtures.ensure(entry, self.dir, (fake("tampered")))
  self:assert_nil(state)
  self:assert_true(problem:find("sha256", 1, true) ~= nil)
  self:assert_nil(read(self.dir .. "/b.txt"))
  self:assert_nil(read(self.dir .. "/b.txt.part"))
end

function T:test_a_stale_file_is_replaced_and_a_failed_download_reports()
  local entry = { name = "c.txt", url = "https://x/c.txt", sha256 = sha256.hex("new") }
  local first = fixtures.ensure({ name = "c.txt", url = entry.url, sha256 = sha256.hex("old") }, self.dir, (fake("old")))
  self:assert_equal("fetched", first)
  self:assert_equal("fetched", (fixtures.ensure(entry, self.dir, (fake("new")))))
  self:assert_equal("new", read(self.dir .. "/c.txt"))
  local state, problem = fixtures.ensure({ name = "d.txt", url = entry.url, sha256 = entry.sha256 }, self.dir, (fake("", false)))
  self:assert_nil(state)
  self:assert_true(problem:find("boom", 1, true) ~= nil)
end

function T:test_a_stale_file_is_deleted_when_the_download_fails()
  local entry = { name = "e.txt", url = "https://x/e.txt", sha256 = sha256.hex("new") }
  write(self.dir .. "/e.txt", "stale content that the pin does not describe")
  local state = fixtures.ensure(entry, self.dir, (fake("", false)))
  self:assert_nil(state)
  self:assert_nil(read(self.dir .. "/e.txt"), "a test must not read a file the pin does not describe")
end

function T:test_a_stale_file_is_deleted_when_the_download_does_not_match()
  local entry = { name = "f.txt", url = "https://x/f.txt", sha256 = sha256.hex("new") }
  write(self.dir .. "/f.txt", "stale")
  self:assert_nil((fixtures.ensure(entry, self.dir, (fake("other")))))
  self:assert_nil(read(self.dir .. "/f.txt"))
  self:assert_nil(read(self.dir .. "/f.txt.part"))
end

function T:test_a_leftover_part_file_is_removed_before_the_download()
  local entry = { name = "g.txt", url = "https://x/g.txt", sha256 = sha256.hex("new") }
  write(self.dir .. "/g.txt.part", "interrupted")
  -- The download writes nothing and succeeds: the old part must not be taken for its output.
  local silent = function() return "", true end
  local state, problem = fixtures.ensure(entry, self.dir, silent)
  self:assert_nil(state)
  self:assert_true(problem:find("empty", 1, true) ~= nil, problem)
  self:assert_nil(read(self.dir .. "/g.txt.part"))
  write(self.dir .. "/g.txt.part", "interrupted")
  self:assert_equal("fetched", (fixtures.ensure(entry, self.dir, (fake("new")))))
  self:assert_nil(read(self.dir .. "/g.txt.part"))
end

function T:test_an_empty_download_is_a_failure_even_when_the_pin_is_the_empty_digest()
  local entry = { name = "h.txt", url = "https://x/h.txt", sha256 = sha256.hex("") }
  write(self.dir .. "/h.txt", "stale")
  local state, problem = fixtures.ensure(entry, self.dir, (fake("")))
  self:assert_nil(state)
  self:assert_true(problem:find("empty", 1, true) ~= nil)
  self:assert_nil(read(self.dir .. "/h.txt"))
end

function T:test_a_download_over_the_limit_is_refused_before_it_is_read()
  local entry = { name = "i.txt", url = "https://x/i.txt", sha256 = sha256.hex("0123456789"), max_bytes = 5 }
  local state, problem = fixtures.ensure(entry, self.dir, (fake("0123456789")))
  self:assert_nil(state)
  self:assert_true(problem:find("larger than 5 bytes", 1, true) ~= nil, problem)
  self:assert_nil(read(self.dir .. "/i.txt"))
  self:assert_nil(read(self.dir .. "/i.txt.part"))
end

function T:test_an_oversized_file_already_there_is_not_taken_for_the_cached_one()
  local entry = { name = "j.txt", url = "https://x/j.txt", sha256 = sha256.hex("0123456789"), max_bytes = 5 }
  write(self.dir .. "/j.txt", "0123456789")
  local download, calls = fake("12345")
  self:assert_nil((fixtures.ensure(entry, self.dir, download)))
  self:assert_equal(1, calls.n, "the matching but oversized file is downloaded again, not trusted")
end

function T:test_a_bad_shape_gives_no_download_call()
  local download, calls = fake("content")
  for _, entry in ipairs({
    with({ url = "http://x/a" }), with({ url = "https://x/a b" }), with({ name = "../a" }), with({ sha256 = "abc" }),
    { name = "g", repository = "https://x/r", commit = COMMIT },
  }) do
    local state, problem = fixtures.ensure(entry, self.dir, download)
    self:assert_nil(state)
    self:assert_not_nil(problem)
  end
  self:assert_equal(0, calls.n)
end

function T:test_the_retry_wraps_the_download()
  local entry = { name = "k.txt", url = "https://x/k.txt", sha256 = sha256.hex("ok") }
  local tries = 0
  local download = function(_, path)
    tries = tries + 1
    if tries < 3 then return "transient", false end
    write(path, "ok")
    return "", true
  end
  local retry = function(step)
    local out, ok
    for _ = 1, 3 do
      out, ok = step()
      if ok then break end
    end
    return out, ok
  end
  self:assert_equal("fetched", (fixtures.ensure(entry, self.dir, download, retry)))
  self:assert_equal(3, tries)
end

return T
