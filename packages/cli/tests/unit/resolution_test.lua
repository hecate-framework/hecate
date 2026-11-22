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

local MANIFEST = [[
rock_manifest = {
   ["plc-0.5-1.rockspec"] = "067ce63077288934f39ba5f7d107392c",
   doc = { LICENSE = "5399427ba376414805b65efd583c410c" },
   lua = { plc = { ["sha2.lua"] = "02f7", ["bin.lua"] = "d8c7" }, ["top.lua"] = "aaaa" },
   lib = { ["x.so"] = "bbbb" },
   bin = { tool = "cccc" },
}
]]

local function files_of(map)
  return function(category, path) return map[category .. "/" .. path] end
end

local FILES = { ["lua/plc/sha2.lua"] = "SHA2", ["lua/plc/bin.lua"] = "BIN", ["lua/top.lua"] = "TOP", ["lib/x.so"] = "SO", ["bin/tool"] = "TOOL" }

function T:test_the_digest_of_installed_files_follows_the_files_not_the_documentation()
  local function digest(files, manifest)
    -- The real SHA-256: the fake one of this file depends on lengths only.
    return resolution.installed_files_digest({ manifest_text = manifest or MANIFEST, read_file = files_of(files) })
  end
  local first = digest(FILES)
  self:assert_equal(64, #first)
  self:assert_equal(first, digest(FILES))
  local changed = {}
  for k, v in pairs(FILES) do changed[k] = v end
  changed["lua/plc/sha2.lua"] = "SHA2 but changed in length"
  self:assert_true(first ~= digest(changed))
  -- The documentation is not read at all: a manifest listing it hashes the same as one that does not.
  local without_doc = MANIFEST:gsub('   doc = { LICENSE = "5399427ba376414805b65efd583c410c" },\n', "")
  self:assert_equal(first, digest(FILES, without_doc))
end

function T:test_the_digest_of_installed_files_has_a_fixed_layout()
  local manifest = 'rock_manifest = { lua = { ["a.lua"] = "x" } }'
  local digest = resolution.installed_files_digest({ manifest_text = manifest, read_file = files_of({ ["lua/a.lua"] = "abc" }) })
  -- The sha256 (checked with `sha256sum`) of the line "ba7816bf...15ad  lua/a.lua\n", whose first part is the sha256 of "abc".
  self:assert_equal("f21b989a145290e1711a57d61760c689e2bf0c4d2f2eb41feba3b83bee83ba35", digest)
end

function T:test_no_installed_file_gives_no_digest_and_a_missing_one_is_an_error()
  self:assert_nil(resolution.installed_files_digest({ manifest_text = 'rock_manifest = { doc = { A = "x" } }', read_file = files_of({}), sha256 = fake_sha }))
  local err = self:assert_error(function()
    resolution.installed_files_digest({ manifest_text = MANIFEST, read_file = files_of({}), sha256 = fake_sha })
  end)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find("is missing", 1, true) ~= nil)
  self:assert_error(function() resolution.installed_files_digest({ manifest_text = "rock_manifest = ", read_file = files_of({}) }) end)
  self:assert_error(function() resolution.installed_files_digest({ manifest_text = "x = 1", read_file = files_of({}) }) end)
end

function T:test_pure_rocks_are_checked_by_their_files_and_native_ones_by_their_rockspec()
  local data = input()
  data.files_digests = { ["hecate-core"] = string.rep("1", 64), luv = string.rep("2", 64) }
  local lock = resolution.build_lockfile(data)
  self:assert_equal("files", lock.rocks["hecate-core"].checksum_of)
  self:assert_equal(string.rep("1", 64), lock.rocks["hecate-core"].sha256)
  self:assert_equal("rockspec", lock.rocks.luv.checksum_of)             -- native: the digest is ignored
  self:assert_equal(fake_sha(LUV), lock.rocks.luv.sha256)
  self:assert_equal("rockspec", lock.rocks["hecate-kernel"].checksum_of) -- no digest given
end

function T:test_verify_compares_what_is_installed_with_the_lock()
  local data = input()
  data.files_digests = { ["hecate-core"] = string.rep("1", 64) }
  local lock = resolution.build_lockfile(data)
  local function current()
    local list = {}
    for name, text in pairs(data.rockspecs) do list[name] = { rockspec = text } end
    list["hecate-core"].files_digest = string.rep("1", 64)
    return list
  end
  self:assert_equal(0, #resolution.verify(lock, current(), fake_sha))

  local changed_files = current()
  changed_files["hecate-core"].files_digest = string.rep("9", 64)
  local problems = resolution.verify(lock, changed_files, fake_sha)
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("installed files differ", 1, true) ~= nil, problems[1])
  self:assert_true(problems[1]:find("hecate update hecate-core", 1, true) ~= nil)

  local changed_rockspec = current()
  changed_rockspec.luv.rockspec = LUV .. "-- tampered\n"
  self:assert_true(resolution.verify(lock, changed_rockspec, fake_sha)[1]:find("its rockspec differs", 1, true) ~= nil)

  local missing = current()
  missing["hecate-test"] = nil
  self:assert_true(resolution.verify(lock, missing, fake_sha)[1]:find("not installed", 1, true) ~= nil)
end

function T:test_the_real_digest_is_the_default()
  local data = input()
  data.sha256 = nil
  local lock = resolution.build_lockfile(data)
  self:assert_equal(64, #lock.rocks.luv.sha256)
  self:assert_true(lock.rocks.luv.sha256:match("^%x+$") ~= nil)
end

return T
