local test = require("harness.test")
local luarocks = require("hecate.cli.luarocks")
local installer = require("hecate.cli.installer")
local T = test.Case("CliInstallerTest")

local function fake_sha(data)
  local sum = 0
  for index = 1, #data do sum = (sum * 31 + data:byte(index)) % 4294967296 end
  return string.rep(string.format("%08x", sum), 8)
end

local MANIFEST = 'return { name = "app", version = "0.1.0", dependencies = { plc = "~> 0.5" } }'
local ROCKSPEC = 'package = "plc"\nversion = "0.5-1"\nsource = { url = "git+https://example.test/plc.git" }\ndependencies = { "lua >= 5.1" }\nbuild = { type = "builtin", modules = { plc = "plc.lua" } }\n'
local ROCK_MANIFEST = 'rock_manifest = { lua = { ["plc.lua"] = "x" }, ["plc-0.5-1.rockspec"] = "y" }'

--- An in-memory file system and a runner that behaves like LuaRocks for one rock.
local function setup()
  local files = {
    ["lua_modules/lib/luarocks/rocks-5.5/plc/0.5-1/plc-0.5-1.rockspec"] = ROCKSPEC,
    ["lua_modules/lib/luarocks/rocks-5.5/plc/0.5-1/rock_manifest"] = ROCK_MANIFEST,
    ["lua_modules/share/lua/5.5/plc.lua"] = "return {}",
  }
  local calls = {}
  local function runner(_, args)
    calls[#calls + 1] = table.concat(args, " ")
    if args[3] == "build" then files[".hecate/luarocks/luarocks.lock"] = 'return { dependencies = { lua = "5.5-1", plc = "0.5-1" } }' end
    return { code = 0, stdout = args[3] == "list" and "plc\t0.5-1\tinstalled\t/x\n" or "", stderr = "" }
  end
  local fs = {
    read = function(path) return files[path] end,
    write = function(path, text) files[path] = text end,
  }
  return {
    files = files, calls = calls,
    options = function(extra)
      local options = {
        manifest_text = MANIFEST, fs = fs, work_dir = ".hecate/luarocks", tree = "lua_modules", lua = "5.5", luarocks_version = "3.13.0", sha256 = fake_sha,
        luarocks = luarocks.new({ runner = runner, tree = "lua_modules", config_dir = ".hecate/luarocks" }),
      }
      for key, value in pairs(extra or {}) do options[key] = value end
      return options
    end,
  }
end

function T:test_installs_pins_and_returns_the_lockfile()
  local world = setup()
  local result = installer.install(world.options())
  self:assert_equal(1, result.installed)
  self:assert_equal("0.5-1", result.lock.rocks.plc.version)
  self:assert_equal("files", result.lock.rocks.plc.checksum_of)
  self:assert_true(world.files[".hecate/luarocks/config.lua"] ~= nil)
  self:assert_true(world.files[".hecate/luarocks/app-0.1.0-1.rockspec"] ~= nil)
  self:assert_true(world.calls[1]:find("install --deps-only", 1, true) ~= nil)
  self:assert_true(world.calls[#world.calls]:find("build --pin --only-deps", 1, true) ~= nil)
end

function T:test_frozen_without_a_lockfile_stops_before_installing()
  local world = setup()
  self:assert_error(function() installer.install(world.options({ frozen = true })) end)
  self:assert_equal(0, #world.calls)
end

function T:test_frozen_accepts_what_it_locked_and_detects_a_changed_file()
  local world = setup()
  local first = installer.install(world.options())
  local again = installer.install(world.options({ frozen = true, lock_text = first.lock_text }))
  self:assert_equal(first.lock_text, again.lock_text)
  world.files["lua_modules/share/lua/5.5/plc.lua"] = "return { tampered = true }"
  local err = self:assert_error(function() installer.install(world.options({ frozen = true, lock_text = first.lock_text })) end)
  self:assert_true(tostring(err.message):find("does not match hecate.lock", 1, true) ~= nil)
end
return T
