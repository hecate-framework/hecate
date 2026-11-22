local test = require("harness.test")
local core = require("hecate.core")
local resolution = require("hecate.cli.resolution")
local lockfile = require("hecate.cli.lockfile")
local T = test.Case("CliResolutionTest")

local function fake_sha(data) return string.rep(string.format("%02x", #data % 256), 32) end

local PURE = [[
package = "hecate-core"
version = "0.1.0-1"
source = { url = "git+https://github.com/hecate-framework/hecate-core.git", tag = "v0.1.0" }
dependencies = { "lua >= 5.5, < 5.6" }
build = { type = "builtin", modules = { ["hecate.core"] = "src/hecate/core/init.lua" } }
]]
local KERNEL = [[
package = "hecate-kernel"
version = "0.1.0-1"
source = { url = "git+https://github.com/hecate-framework/hecate-kernel.git" }
dependencies = { "lua >= 5.5", "hecate-core ~> 0.1", "LUV >= 1.50", "unknownrock" }
build = { type = "builtin", modules = {} }
]]
local LUV = [[
package = "luv"
version = "1.53.0-0"
source = { url = "https://github.com/luvit/luv/releases/download/1.53.0-0/luv-1.53.0-0.tar.gz" }
dependencies = { "lua >= 5.1" }
build = { type = "cmake" }
]]
local TEST = [[
package = "hecate-test"
version = "0.1.0-1"
source = { url = "git+https://github.com/hecate-framework/hecate-test.git" }
dependencies = { "hecate-core ~> 0.1" }
build = { type = "builtin", modules = { x = { sources = { "x.c" } } } }
]]

local function input()
  return {
    manifest = { name = "app", dependencies = { ["hecate-kernel"] = "~> 0.1" }, development_dependencies = { ["hecate-test"] = "~> 0.1" } },
    pins = { ["hecate-kernel"] = "0.1.0-1", ["hecate-core"] = "0.1.0-1", luv = "1.53.0-0", ["hecate-test"] = "0.1.0-1" },
    rockspecs = { ["hecate-kernel"] = KERNEL, ["hecate-core"] = PURE, luv = LUV, ["hecate-test"] = TEST },
    lua = "5.5.1", luarocks = "3.13.0", sha256 = fake_sha,
  }
end

function T:test_facts_of_a_rockspec()
  local facts = resolution.read_rockspec("hecate-kernel", KERNEL)
  self:assert_equal("git+https://github.com/hecate-framework/hecate-kernel.git", facts.source)
  self:assert_equal("hecate-core,luv,unknownrock", table.concat(facts.dependencies, ","))  -- lower case, no `lua`
  self:assert_false(facts.native)
  self:assert_true(resolution.read_rockspec("luv", LUV).native)            -- a cmake build
  self:assert_true(resolution.read_rockspec("hecate-test", TEST).native)   -- a module with C sources
  self:assert_false(resolution.read_rockspec("hecate-core", PURE).native)  -- a Lua file
end

function T:test_unreadable_rockspecs_name_the_rock()
  local function bad(text, fragment)
    local err = self:assert_error(function() resolution.read_rockspec("odd", text) end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
    self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find(fragment, 1, true) ~= nil)
  end
  bad("package = ", "odd.rockspec")
  bad('package = "odd"', "no source.url")
  bad('source = { url = "" }', "no source.url")
  bad('source = { url = os.getenv("X") }', "odd.rockspec")
  bad("while true do end", "instruction limit")
end

function T:test_the_lockfile_of_an_installation()
  local lock = resolution.build_lockfile(input())
  self:assert_equal(1, lock.format)
  self:assert_equal("5.5.1", lock.lua)
  local kernel = lock.rocks["hecate-kernel"]
  self:assert_equal("0.1.0-1", kernel.version)
  self:assert_equal("hecate-core,luv", table.concat(kernel.dependencies, ","))   -- `unknownrock` is not pinned: no edge
  self:assert_false(kernel.development)
  self:assert_false(lock.rocks.luv.development)
  self:assert_true(lock.rocks.luv.native)
  self:assert_false(lock.rocks["hecate-core"].development)                      -- reached at run time as well
  self:assert_true(lock.rocks["hecate-test"].development)
  self:assert_equal(fake_sha(KERNEL), kernel.sha256)
  self:assert_equal(0, #lockfile.outdated(lock, input().manifest))
  self:assert_equal(lockfile.serialize(lock), lockfile.serialize(lockfile.parse(lockfile.serialize(lock))))
end

function T:test_a_rock_reached_only_by_development_dependencies_is_development()
  local data = input()
  data.manifest.dependencies = { ["hecate-core"] = "~> 0.1" }
  local lock = resolution.build_lockfile(data)
  self:assert_true(lock.rocks["hecate-kernel"].development)
  self:assert_true(lock.rocks.luv.development)
  self:assert_false(lock.rocks["hecate-core"].development)
end

function T:test_missing_pins_and_rockspecs_are_errors_that_name_the_rock()
  local data = input()
  data.pins["hecate-kernel"] = nil
  local err = self:assert_error(function() resolution.build_lockfile(data) end)
  self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find("'hecate-kernel'", 1, true) ~= nil)

  local missing = input()
  missing.rockspecs.luv = nil
  local err2 = self:assert_error(function() resolution.build_lockfile(missing) end)
  self:assert_true(tostring((err2 --[[@as hecate.core.Error]]).message):find("'luv'", 1, true) ~= nil)

  local dev = input()
  dev.pins["hecate-test"] = nil
  dev.rockspecs["hecate-test"] = nil
  local err3 = self:assert_error(function() resolution.build_lockfile(dev) end)
  self:assert_true(tostring((err3 --[[@as hecate.core.Error]]).message):find("development dependency", 1, true) ~= nil)
end

function T:test_the_real_digest_is_the_default()
  local data = input()
  data.sha256 = nil
  local lock = resolution.build_lockfile(data)
  self:assert_equal(64, #lock.rocks.luv.sha256)
  self:assert_true(lock.rocks.luv.sha256:match("^%x+$") ~= nil)
end

return T
