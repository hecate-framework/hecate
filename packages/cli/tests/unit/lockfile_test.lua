local test = require("harness.test")
local core = require("hecate.core")
local lockfile = require("hecate.cli.lockfile")
local T = test.Case("CliLockfileTest")

local SHA = string.rep("ab", 32)

local function rock(overrides)
  local value = { version = "0.1.0-1", source = "https://luarocks.org/hecate-core-0.1.0-1.src.rock", sha256 = SHA,
    dependencies = {}, development = false, native = false }
  for k, v in pairs(overrides or {}) do value[k] = v end
  return value
end

local function sample()
  return {
    format = 1, lua = "5.5.1", luarocks = "3.13.0",
    rocks = {
      ["hecate-kernel"] = rock({ version = "0.1.4-1", dependencies = { "hecate-core", "luv" } }),
      ["hecate-core"] = rock(),
      luv = rock({ native = true, version = "1.52.0-1" }),
      ["hecate-test"] = rock({ version = "0.1.0-1", development = true, dependencies = { "hecate-core" } }),
    },
  }
end

local function rejects(self, run, fragment)
  local err = self:assert_error(run)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find(fragment, 1, true) ~= nil, message)
end

function T:test_serialization_is_sorted_and_round_trips()
  local text = lockfile.serialize(sample())
  self:assert_true(text:find('["hecate-core"] = {', 1, true) < text:find('["hecate-kernel"] = {', 1, true))
  self:assert_true(text:find("luv = {", 1, true) ~= nil)
  self:assert_true(text:find('dependencies = { "hecate-core", "luv" },', 1, true) ~= nil)
  self:assert_equal(text, lockfile.serialize(lockfile.parse(text)))
  self:assert_equal(text, lockfile.serialize(sample()))
end

function T:test_the_same_content_gives_the_same_bytes_whatever_the_order_of_dependencies()
  local a, b = sample(), sample()
  b.rocks["hecate-kernel"].dependencies = { "luv", "hecate-core" }
  self:assert_equal(lockfile.serialize(a), lockfile.serialize(b))
end

function T:test_schema_violations_name_their_pointer()
  local bad = sample()
  bad.rocks.luv.sha256 = "xyz"
  bad.extra = true
  bad.format = 2
  local err = self:assert_error(function() lockfile.validate(bad) end)
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find("/rocks/luv/sha256", 1, true) ~= nil, message)
  self:assert_true(message:find("/format", 1, true) ~= nil, message)
  self:assert_true(message:find("extra", 1, true) ~= nil, message)
end

function T:test_uppercase_checksums_and_dangling_edges_are_refused()
  local upper = sample()
  upper.rocks.luv.sha256 = string.rep("AB", 32)
  rejects(self, function() lockfile.validate(upper) end, "lowercase")
  local dangling = sample()
  dangling.rocks.luv.dependencies = { "ghost" }
  rejects(self, function() lockfile.validate(dangling) end, "'ghost' is not in the lockfile")
end

function T:test_parse_runs_in_an_empty_environment()
  rejects(self, function() lockfile.parse('return { format = require("x") }') end, "require")
  rejects(self, function() lockfile.parse("return {") end, "hecate.lock")
  rejects(self, function() lockfile.parse("return 3") end, "must return a table")
end

function T:test_special_characters_in_strings_are_escaped()
  local lock = sample()
  lock.rocks.luv.source = 'https://x.test/a"b\\c\n\1'
  local back = lockfile.parse(lockfile.serialize(lock))
  self:assert_equal(lock.rocks.luv.source, back.rocks.luv.source)
end

function T:test_outdated_detects_what_install_frozen_must_refuse()
  local manifest = { name = "app", dependencies = { ["hecate-kernel"] = "~> 0.1" }, development_dependencies = { ["hecate-test"] = "~> 0.1" } }
  self:assert_equal(0, #lockfile.outdated(sample(), manifest))

  local missing = sample()
  missing.rocks["hecate-test"] = nil
  local problems = lockfile.outdated(missing, manifest)
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("run `hecate install`", 1, true) ~= nil)

  local orphan = sample()
  orphan.rocks.stray = rock()
  self:assert_true(lockfile.outdated(orphan, manifest)[1]:find("'stray'", 1, true) ~= nil)

  local wrong_flag = sample()
  wrong_flag.rocks["hecate-core"].development = true
  self:assert_true(lockfile.outdated(wrong_flag, manifest)[1]:find("needed at run time", 1, true) ~= nil)

  local stale = sample()
  stale.rocks["hecate-kernel"].version = "0.2.0-1"
  local stale_problems = lockfile.outdated(stale, manifest)
  self:assert_equal(1, #stale_problems)
  self:assert_true(stale_problems[1]:find("locked at 0.2.0-1", 1, true) ~= nil, stale_problems[1])
  self:assert_true(stale_problems[1]:find("'~> 0.1'", 1, true) ~= nil)

  local not_dev = sample()
  not_dev.rocks["hecate-test"].development = false
  self:assert_true(lockfile.outdated(not_dev, manifest)[1]:find("only needed for development", 1, true) ~= nil)
end

return T
