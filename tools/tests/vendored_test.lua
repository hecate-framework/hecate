---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local vendored = require("lib.vendored")
local licenses = require("lib.licenses")
local sha256 = require("lib.sha256")
local sha512 = require("lib.sha512")
local util = require("lib.util")
local task = require("tasks.check_vendored")
local T = test.Case("VendoredTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")

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

local TARBALL = "pretend tarball bytes"
local INTEGRITY = sha512.integrity(TARBALL)
local SHASUM = ("ab"):rep(20)

-- The text of a VENDORED.md for the package `lib@1.2.3` with the files `lib.js` and `LICENSE`.
local function vendored_md(overrides)
  overrides = overrides or {}
  return table.concat({
    "# Vendored: lib",
    "",
    "| File | SHA-256 |",
    "| --- | --- |",
    ("| `lib.js` | `%s` |"):format(overrides.js_digest or sha256.hex("js body")),
    ("| `LICENSE` | `%s` |"):format(sha256.hex("licence")),
    "",
    "| Package | Version | `dist.integrity` | `dist.shasum` |",
    "| --- | --- | --- | --- |",
    ("| `%s` | `1.2.3` | `%s` | `%s` |"):format(overrides.name or "lib", overrides.integrity or INTEGRITY, overrides.shasum or SHASUM),
    "",
    "| Vendored file | Package | Path in the package |",
    "| --- | --- | --- |",
    ("| `lib.js` | `%s` | `%s` |"):format(overrides.package or "lib", overrides.path or "dist/lib.js"),
    ("| `LICENSE` | `lib` | `LICENSE` |"),
    "",
  }, "\n")
end

function T:test_the_package_and_file_rows_are_read()
  local text = vendored_md()
  local packages, files = vendored.packages(text), vendored.files(text)
  self:assert_equal(1, #packages)
  self:assert_equal("lib", packages[1].name)
  self:assert_equal("1.2.3", packages[1].version)
  self:assert_equal(INTEGRITY, packages[1].integrity)
  self:assert_equal(SHASUM, packages[1].shasum)
  self:assert_equal(2, #files)
  self:assert_equal("lib.js", files[1].file)
  self:assert_equal("dist/lib.js", files[1].path)
  self:assert_equal(2, #licenses.digests(text), "the provenance tables are not digest rows")
  self:assert_equal(0, #vendored.problems("d", text, licenses.digests(text)))
  local crlf = vendored_md():gsub("\n", "\r\n")
  self:assert_equal(1, #vendored.packages(crlf))
  self:assert_equal(2, #vendored.files(crlf))
  self:assert_equal(2, #licenses.digests(crlf))
end

function T:test_the_tarball_url_of_a_scoped_and_an_unscoped_package()
  self:assert_equal("https://registry.npmjs.org/mermaid/-/mermaid-12.3.0.tgz", vendored.tarball_url("mermaid", "12.3.0"))
  self:assert_equal("https://registry.npmjs.org/@fontsource/inter/-/inter-5.3.0.tgz",
    vendored.tarball_url("@fontsource/inter", "5.3.0"))
end

function T:test_the_path_inside_a_package_must_stay_inside()
  for _, path in ipairs({ "dist/mermaid.min.js", "files/inter-latin-400-normal.woff2", "LICENSE", "a/b.c" }) do
    self:assert_true(vendored.safe_path(path), path)
  end
  for _, path in ipairs({ "", "/etc/passwd", "../x", "a/../x", "a/./b", "a b", "a;b", "a'b", 'a"b', "a%b", "a\\b" }) do
    self:assert_false(vendored.safe_path(path), path)
  end
end

local function problems_of(overrides)
  local text = vendored_md(overrides)
  return vendored.problems("d", text, licenses.digests(text))
end

function T:test_a_malformed_record_is_reported()
  self:assert_equal(1, #problems_of({ integrity = "sha512-abc==" }))
  self:assert_equal(1, #problems_of({ integrity = "sha1-" .. ("A"):rep(88) }), "an integrity that is not SHA-512")
  self:assert_equal(1, #problems_of({ shasum = ("ab"):rep(19) }))
  self:assert_equal(1, #problems_of({ shasum = ("AB"):rep(20) }), "upper case")
  self:assert_true(#problems_of({ name = "../x" }) >= 1, "a package name is not a path")
  local escaped = problems_of({ path = "../../etc/passwd" })
  self:assert_equal(1, #escaped)
  self:assert_true(escaped[1]:find("stay inside", 1, true) ~= nil)
  local unknown = problems_of({ package = "other" })
  self:assert_true(#unknown >= 1)
  self:assert_true(unknown[1]:find("other", 1, true) ~= nil)
end

function T:test_a_file_without_a_digest_a_duplicate_package_or_an_unused_package_is_reported()
  local text = vendored_md():gsub("| `LICENSE` | `[%x]+` |\n", "", 1)
  local problems = vendored.problems("d", text, licenses.digests(text))
  self:assert_equal(1, #problems, table.concat(problems, "; "))
  self:assert_true(problems[1]:find("LICENSE has no row", 1, true) ~= nil, problems[1])
  local twice = vendored_md():gsub("(| `lib` | `1.2.3` | `[^\n]*\n)", "%1%1", 1)
  local twice_problems = vendored.problems("d", twice, licenses.digests(twice))
  self:assert_equal(1, #twice_problems)
  self:assert_true(twice_problems[1]:find("recorded twice", 1, true) ~= nil)
  local unused = vendored_md():gsub("\n%| `lib.js` | `lib` | [^\n]*", "", 1):gsub("\n%| `LICENSE` | `lib` | [^\n]*", "", 1)
  local unused_problems = vendored.problems("d", unused, licenses.digests(unused))
  self:assert_equal(1, #unused_problems, table.concat(unused_problems, "; "))
  self:assert_true(unused_problems[1]:find("records no vendored file", 1, true) ~= nil, unused_problems[1])
  self:assert_equal(0, #vendored.problems("d", "# no npm record\n", {}), "a directory that does not come from npm has no record")
end

-- A temporary root with one vendored directory (`packages/p/vendor` or `examples/e/fonts`) holding the files of the text.
function T:set_up()
  self.root = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "vendored-test"))
  self.dir = "packages/p/assets"
  self.example = "examples/e/fonts"
  util.mkdir(self.root .. "/" .. self.dir)
  write(self.root .. "/" .. self.dir .. "/lib.js", "js body")
  write(self.root .. "/" .. self.dir .. "/LICENSE", "licence")
  write(self.root .. "/" .. self.dir .. "/VENDORED.md", vendored_md())
  self.downloads, self.extracts, self.pauses = {}, 0, 0
  self.tarball = TARBALL
  self.unpacked = { ["dist/lib.js"] = "js body", ["LICENSE"] = "licence" }
  self.download_ok, self.extract_ok = true, true
end

function T:tear_down() util.remove_tree(self.root) end

function T:run(...)
  return task.run({
    root = self.root,
    args = { ... },
    download = function(url, path, max)
      self.downloads[#self.downloads + 1] = { url = url, max = max }
      if not self.download_ok then return "unreachable", false end
      write(path, self.tarball)
      return "", true
    end,
    extract = function(_, directory)
      self.extracts = self.extracts + 1
      if not self.extract_ok then return "bad archive", false end
      util.mkdir(directory .. "/package/dist")
      for path, content in pairs(self.unpacked) do write(directory .. "/package/" .. path, content) end
      return "", true
    end,
    pause = function() self.pauses = self.pauses + 1 end,
  })
end

local function scratch()
  local found = {}
  for _, name in ipairs(util.list_dir(ROOT .. "/.hecate/tmp")) do
    if name:find("^vendored%-%d") then found[#found + 1] = name end
  end
  return #found
end

function T:test_offline_verifies_the_digests_and_the_records_without_the_network()
  local report = self:run()
  self:assert_true(report.ok, table.concat(report.problems, "; "))
  self:assert_equal(false, report.data.online)
  self:assert_equal("recorded", report.data.directories[1].packages[1].state)
  self:assert_equal(0, #self.downloads)
  write(self.root .. "/" .. self.dir .. "/lib.js", "tampered")
  local tampered = self:run()
  self:assert_false(tampered.ok)
  self:assert_equal(1, #tampered.problems)
  self:assert_true(tampered.problems[1]:find("lib.js: SHA-256 differs", 1, true) ~= nil, tampered.problems[1])
  self:assert_equal(0, #self.downloads)
end

function T:test_offline_covers_the_examples_too()
  util.mkdir(self.root .. "/" .. self.example)
  write(self.root .. "/" .. self.example .. "/lib.js", "js body")
  write(self.root .. "/" .. self.example .. "/LICENSE", "licence")
  write(self.root .. "/" .. self.example .. "/VENDORED.md", vendored_md({ js_digest = ("0"):rep(64) }))
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(2, #report.data.directories)
  self:assert_equal(self.example, report.data.directories[1].dir)
  self:assert_true(report.problems[1]:find(self.example .. "/lib.js: SHA-256 differs", 1, true) ~= nil, report.problems[1])
end

function T:test_a_malformed_record_fails_offline()
  write(self.root .. "/" .. self.dir .. "/VENDORED.md", vendored_md({ integrity = "sha512-short==" }))
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("dist.integrity", 1, true) ~= nil, report.problems[1])
end

function T:test_an_unknown_argument_is_a_usage_error()
  for _, args in ipairs({ { "--bogus" }, { "online" }, { "--online", "x" } }) do
    local report = self:run(table.unpack(args))
    self:assert_false(report.ok)
    self:assert_true(report.problems[1]:find("usage: check-vendored [--online]", 1, true) ~= nil)
  end
  self:assert_equal(0, #self.downloads)
end

function T:test_online_downloads_the_recorded_tarball_and_compares_the_files()
  local before = scratch()
  local report = self:run("--online")
  self:assert_true(report.ok, table.concat(report.problems, "; "))
  self:assert_equal("verified", report.data.directories[1].packages[1].state)
  self:assert_equal(1, #self.downloads)
  self:assert_equal("https://registry.npmjs.org/lib/-/lib-1.2.3.tgz", self.downloads[1].url)
  self:assert_equal(64 * 1024 * 1024, self.downloads[1].max)
  self:assert_equal(1, self.extracts)
  self:assert_equal(before, scratch(), "the scratch directory is removed")
end

function T:test_online_reports_a_tarball_whose_integrity_differs_and_does_not_unpack_it()
  self.tarball = "a different tarball"
  local report = self:run("--online")
  self:assert_false(report.ok)
  self:assert_equal(1, #report.problems)
  self:assert_true(report.problems[1]:find("dist.integrity " .. sha512.integrity(self.tarball), 1, true) ~= nil, report.problems[1])
  self:assert_true(report.problems[1]:find("recorded " .. INTEGRITY, 1, true) ~= nil)
  self:assert_equal(0, self.extracts)
  self:assert_equal("failed", report.data.directories[1].packages[1].state)
end

function T:test_online_reports_a_file_that_differs_from_the_recorded_digest_or_is_missing()
  self.unpacked["dist/lib.js"] = "replaced upstream"
  local report = self:run("--online")
  self:assert_false(report.ok)
  self:assert_equal(1, #report.problems)
  self:assert_true(report.problems[1]:find("dist/lib.js of the tarball does not have the SHA-256 recorded for lib.js", 1, true) ~= nil,
    report.problems[1])
  self.unpacked["dist/lib.js"] = nil
  local missing = self:run("--online")
  self:assert_false(missing.ok)
  self:assert_true(missing.problems[1]:find("has no file dist/lib.js", 1, true) ~= nil, missing.problems[1])
end

function T:test_online_retries_a_failed_download_and_reports_it()
  self.download_ok = false
  local before = scratch()
  local report = self:run("--online")
  self:assert_false(report.ok)
  self:assert_equal(3, #self.downloads)
  self:assert_equal(2, self.pauses)
  self:assert_true(report.problems[1]:find("unreachable", 1, true) ~= nil)
  self:assert_equal(0, self.extracts)
  self:assert_equal(before, scratch())
end

function T:test_online_reports_an_empty_download_and_an_archive_that_cannot_be_unpacked()
  self.tarball = ""
  local empty = self:run("--online")
  self:assert_false(empty.ok)
  self:assert_true(empty.problems[1]:find("empty", 1, true) ~= nil, empty.problems[1])
  self.tarball = TARBALL
  self.extract_ok = false
  local bad = self:run("--online")
  self:assert_false(bad.ok)
  self:assert_true(bad.problems[1]:find("cannot unpack", 1, true) ~= nil, bad.problems[1])
  self:assert_equal(0, scratch())
end

-- The real `tar` (Linux, macOS and Windows 10 and later) unpacks a tarball written by `tar`: the same call as the task's.
function T:test_the_default_extraction_unpacks_a_real_tarball()
  local tar = util.tar_command()
  local _, have_tar = util.capture(tar .. " --version")
  if not have_tar then return end
  local source = self.root .. "/src"
  util.mkdir(source .. "/package/dist")
  write(source .. "/package/dist/lib.js", "js body")
  write(source .. "/package/LICENSE", "licence")
  local archive = self.root .. "/real.tgz"
  local _, packed = util.capture(("%s -czf %s -C %s package 2>&1"):format(tar, util.quote(archive), util.quote(source)))
  self:assert_true(packed)
  local bytes = assert(read(archive))
  local real = task.run({
    root = self.root,
    args = { "--online" },
    download = function(_, path)
      write(path, bytes)
      return "", true
    end,
  })
  self:assert_false(real.ok, "the recorded integrity is the one of the pretend tarball")
  write(self.root .. "/" .. self.dir .. "/VENDORED.md", vendored_md({ integrity = sha512.integrity(bytes) }))
  local ok = task.run({
    root = self.root,
    args = { "--online" },
    download = function(_, path)
      write(path, bytes)
      return "", true
    end,
  })
  self:assert_true(ok.ok, table.concat(ok.problems, "; "))
  self:assert_equal("verified", ok.data.directories[1].packages[1].state)
end

return T
