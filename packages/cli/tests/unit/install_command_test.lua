local test = require("harness.test")
local app = require("hecate.cli.app")
local install = require("hecate.cli.commands.install")
local luarocks = require("hecate.cli.luarocks")
local T = test.Case("CliInstallCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", platform = "linux-x86_64" }
local MANIFEST = 'return { name = "app", version = "0.1.0", dependencies = { plc = "~> 0.5" } }'
local ROCKSPEC = 'package = "plc"\nversion = "0.5-1"\nsource = { url = "git+https://example.test/plc.git" }\ndependencies = { "lua >= 5.1" }\nbuild = { type = "builtin", modules = { plc = "plc.lua" } }\n'

local function sha(data)
  local sum = 0
  for index = 1, #data do sum = (sum * 31 + data:byte(index)) % 4294967296 end
  return string.format("%08x", sum):rep(8)
end

local function world(initial)
  local files = {
    ["lua_modules/lib/luarocks/rocks-5.5/plc/0.5-1/plc-0.5-1.rockspec"] = ROCKSPEC,
    ["lua_modules/lib/luarocks/rocks-5.5/plc/0.5-1/rock_manifest"] = 'rock_manifest = { lua = { ["plc.lua"] = "x" } }',
    ["lua_modules/share/lua/5.5/plc.lua"] = "return {}",
  }
  for path, text in pairs(initial or {}) do files[path] = text end
  local function runner(_, args)
    if args[3] == "build" then files[".hecate/luarocks/luarocks.lock"] = 'return { dependencies = { lua = "5.5-1", plc = "0.5-1" } }' end
    return { code = 0, stdout = args[3] == "list" and "plc\t0.5-1\tinstalled\t/x\n" or "", stderr = "" }
  end
  local dependencies = {
    fs = { read = function(path) return files[path] end, write = function(path, text) files[path] = text end },
    work_dir = ".hecate/luarocks", tree = "lua_modules",
    luarocks = luarocks.new({ runner = runner, tree = "lua_modules", config_dir = ".hecate/luarocks" }),
    sha256 = sha,
    run = function(task) return task() end,
  }
  return files, dependencies
end

local function run(args, dependencies, rt)
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return install.execute(context, dependencies) end }, { __index = install })
  local code = app.run(args, {
    commands = { command }, runtime = rt or runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. tostring(value.installed) .. ":" .. tostring(value.locked) end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

function T:test_install_writes_the_lockfile_and_reports()
  local files, dependencies = world({ ["hecate.project.lua"] = MANIFEST })
  local code, out = run({ "install" }, dependencies)
  self:assert_equal(0, code)
  self:assert_equal("Installed 1 rock(s) into lua_modules; hecate.lock written", out)
  self:assert_true(files["hecate.lock"] ~= nil)
  local _, json = run({ "install", "--json" }, dependencies)
  self:assert_equal("json:1:1", json)
end

function T:test_frozen_verifies_without_rewriting_the_lockfile()
  local files, dependencies = world({ ["hecate.project.lua"] = MANIFEST })
  run({ "install" }, dependencies)
  local locked = files["hecate.lock"]
  local code, out = run({ "install", "--frozen" }, dependencies)
  self:assert_equal(0, code)
  self:assert_true(out:find("verified", 1, true) ~= nil)
  self:assert_equal(locked, files["hecate.lock"])
  files["lua_modules/share/lua/5.5/plc.lua"] = "return { changed = true }"
  local failed, _, err = run({ "install", "--frozen" }, dependencies)
  self:assert_equal(1, failed)
  self:assert_true(err:find("does not match hecate.lock", 1, true) ~= nil)
end

function T:test_a_missing_manifest_names_the_command_that_fixes_it()
  local _, dependencies = world()
  local code, _, err = run({ "install" }, dependencies)
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate new", 1, true) ~= nil)
end

function T:test_without_luarocks_it_says_what_to_do()
  local _, dependencies = world({ ["hecate.project.lua"] = MANIFEST })
  local code, _, err = run({ "install" }, dependencies, { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "x" })
  self:assert_equal(1, code)
  self:assert_true(err:find("LuaRocks was not found", 1, true) ~= nil)
end

function T:test_the_directories_to_create_for_a_path()
  local directories_of = require("hecate.cli.commands.install").directories_of
  local function chain(path) return table.concat(directories_of(path), " ") end
  self:assert_equal(".hecate .hecate/luarocks", chain(".hecate/luarocks/config.lua"))
  self:assert_equal("", chain("hecate.lock"))
  self:assert_equal("/home /home/me /home/me/.hecate", chain("/home/me/.hecate/x"))
  self:assert_equal("C:/Users C:/Users/me", chain("C:/Users/me/x.lua"))
  self:assert_equal("", chain("/x"))
  self:assert_equal("a a/b", chain("a/b/c"))
end

return T
