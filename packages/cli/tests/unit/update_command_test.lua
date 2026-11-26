local test = require("harness.test")
local app = require("hecate.cli.app")
local update = require("hecate.cli.commands.update")
local luarocks = require("hecate.cli.luarocks")
local T = test.Case("CliUpdateCommandTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", platform = "linux-x86_64" }
local MANIFEST = 'return { name = "app", version = "0.1.0", dependencies = { plc = "~> 0.5" } }'

local function sha(data)
  local sum = 0
  for index = 1, #data do sum = (sum * 31 + data:byte(index)) % 4294967296 end
  return string.format("%08x", sum):rep(8)
end

-- The tree holds plc 0.5-1; a removal followed by an installation brings plc 0.5-2, as the servers would.
local function world(initial)
  local files, calls, installed = {}, {}, "0.5-1"
  local function place()
    local directory = "lua_modules/lib/luarocks/rocks-5.5/plc/" .. installed .. "/"
    files[directory .. "plc-" .. installed .. ".rockspec"] = 'package = "plc"\nversion = "' .. installed .. '"\nsource = { url = "git+https://example.test/plc.git" }\ndependencies = { "lua >= 5.1" }\nbuild = { type = "builtin", modules = { plc = "plc.lua" } }\n'
    files[directory .. "rock_manifest"] = 'rock_manifest = { lua = { ["plc.lua"] = "x" } }'
    files["lua_modules/share/lua/5.5/plc.lua"] = "return {}"
  end
  place()
  for path, text in pairs(initial or {}) do files[path] = text end
  local present = true
  local function runner(_, args)
    local verb = args[3]
    calls[#calls + 1] = table.concat(args, " ", 3)
    if verb == "remove" then present = false; return { code = 0, stdout = "", stderr = "" } end
    if verb == "install" and not present then installed = "0.5-2"; place(); present = true end
    if verb == "build" then files[".hecate/luarocks/luarocks.lock"] = 'return { dependencies = { lua = "5.5-1", plc = "' .. installed .. '" } }' end
    return { code = 0, stdout = verb == "list" and (present and ("plc\t" .. installed .. "\tinstalled\t/x\n") or "") or "", stderr = "" }
  end
  local dependencies = {
    fs = { read = function(path) return files[path] end, write = function(path, text) files[path] = text end },
    work_dir = ".hecate/luarocks", tree = "lua_modules",
    luarocks = luarocks.new({ runner = runner, tree = "lua_modules", config_dir = ".hecate/luarocks" }),
    sha256 = sha,
    run = nested.run,
  }
  return files, dependencies, calls
end

local function run(args, dependencies)
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return update.execute(context, dependencies) end }, { __index = update })
  local code = app.run(args, {
    commands = { command }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. #value.updated end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

function T:test_update_takes_the_newer_version_and_reports_it()
  local files, dependencies, calls = world({ ["hecate.project.lua"] = MANIFEST })
  local install = require("hecate.cli.commands.install")
  ---@diagnostic disable-next-line: missing-fields
  install.execute({ runtime = runtime, arguments = { options = {}, positionals = {} }, emit = function() end, print_error = function() end }, dependencies)
  self:assert_true(files["hecate.lock"] ~= nil)
  local code, out = run({ "update" }, dependencies)
  self:assert_equal(0, code)
  self:assert_true(out:find("plc 0.5-1 -> 0.5-2", 1, true) ~= nil)
  self:assert_true(files["hecate.lock"]:find("0.5-2", 1, true) ~= nil)
  local removed = false
  for _, call in ipairs(calls) do if call == "remove --force plc" then removed = true end end
  self:assert_true(removed)
end

function T:test_update_of_one_rock_must_name_a_direct_dependency()
  local _, dependencies = world({ ["hecate.project.lua"] = MANIFEST })
  local code, _, err = run({ "update", "other" }, dependencies)
  self:assert_equal(1, code)
  self:assert_true(err:find("not a direct dependency", 1, true) ~= nil)
  local ok = run({ "update", "plc" }, dependencies)
  self:assert_equal(0, ok)
end

function T:test_a_missing_manifest_and_two_names()
  local _, dependencies = world()
  local code, _, err = run({ "update" }, dependencies)
  self:assert_equal(1, code, err)
  self:assert_true(err:find("hecate new", 1, true) ~= nil)
  self:assert_equal(2, (run({ "update", "a", "b" }, dependencies)))
end

return T
