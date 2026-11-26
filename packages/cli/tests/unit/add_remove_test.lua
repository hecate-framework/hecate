local test = require("harness.test")
local core = require("hecate.core")
local app = require("hecate.cli.app")
local add = require("hecate.cli.commands.add")
local remove = require("hecate.cli.commands.remove")
local luarocks = require("hecate.cli.luarocks")
local T = test.Case("CliAddRemoveTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", platform = "linux-x86_64" }
local MANIFEST = [[
-- My application.
return {
  name = "app",   -- required
  dependencies = {
    -- (none yet)
  },
}
]]

local function rockspec(name, version)
  return ('package = "%s"\nversion = "%s"\nsource = { url = "git+https://example.test/%s.git" }\ndependencies = { "lua >= 5.1" }\nbuild = { type = "builtin", modules = { %s = "%s.lua" } }\n'):format(name, version, name, name, name)
end

local function sha(data)
  local sum = 0
  for index = 1, #data do sum = (sum * 31 + data:byte(index)) % 4294967296 end
  return string.format("%08x", sum):rep(8)
end

--- A project in memory. `versions` maps the rocks LuaRocks can install to their version; `fail` makes the install fail.
local function world(manifest, versions, fail)
  local files = { ["hecate.project.lua"] = manifest }
  local pins = {}
  local function runner(_, args)
    if args[3] == "install" then
      if fail then return { code = 1, stdout = "", stderr = "Error: no results matching query" } end
      -- Install what the generated rockspec asks for.
      local text = files[args[5]] or ""
      pins = {}
      for dependency in text:gmatch('"([%w%-%.]+) [^"]*"') do
        if versions[dependency] then
          pins[dependency] = versions[dependency]
          local directory = "lua_modules/lib/luarocks/rocks-5.5/" .. dependency .. "/" .. versions[dependency]
          files[directory .. "/" .. dependency .. "-" .. versions[dependency] .. ".rockspec"] = rockspec(dependency, versions[dependency])
          files[directory .. "/rock_manifest"] = 'rock_manifest = { lua = { ["' .. dependency .. '.lua"] = "x" } }'
          files["lua_modules/share/lua/5.5/" .. dependency .. ".lua"] = "return {}"
        end
      end
      for dependency in text:gmatch('"([%w%-%.]+)",') do
        if versions[dependency] and not pins[dependency] then pins[dependency] = versions[dependency] end
      end
    end
    if args[3] == "build" then
      local lines = { 'return { dependencies = { lua = "5.5-1"' }
      for name, version in pairs(pins) do lines[#lines + 1] = (', %s = "%s"'):format(name, version) end
      files[".hecate/luarocks/luarocks.lock"] = table.concat(lines) .. " } }"
    end
    local listing = {}
    if args[3] == "list" then
      for name, version in pairs(pins) do listing[#listing + 1] = name .. "\t" .. version .. "\tinstalled\t/x\n" end
    end
    return { code = 0, stdout = table.concat(listing), stderr = "" }
  end
  local environment = {
    fs = { read = function(path) return files[path] end, write = function(path, text) files[path] = text end },
    work_dir = ".hecate/luarocks", tree = "lua_modules",
    luarocks = luarocks.new({ runner = runner, tree = "lua_modules", config_dir = ".hecate/luarocks" }),
    sha256 = sha,
    run = nested.run,
  }
  return files, environment
end

local function run(command, args, environment)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return command.execute(context, environment) end }, { __index = command })
  local code = app.run(args, {
    commands = { wrapped }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. tostring(value.name) .. ":" .. tostring(value.constraint) end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

function T:test_the_default_constraint_is_the_major_and_minor_of_what_was_installed()
  self:assert_equal("~> 0.5", add.default_constraint("0.5-1"))
  self:assert_equal("~> 1.53", add.default_constraint("1.53.0-0"))
  self:assert_equal("~> 3", add.default_constraint("3-1"))
  self:assert_equal("~> 2.10", add.default_constraint("2.10.4.1-2"))
  self:assert_nil(add.default_constraint("scm-1"))
  self:assert_nil(add.default_constraint("dev-1"))
end

function T:test_the_argument_is_a_name_and_maybe_a_constraint()
  local name, wanted = add.split_argument("PLC")
  self:assert_equal("plc", name)
  self:assert_nil(wanted)
  local n2, w2 = add.split_argument("plc@~> 0.5")
  self:assert_equal("plc", n2)
  self:assert_equal("~> 0.5", w2)
  local function bad(argument, fragment)
    local err = self:assert_error(function() add.split_argument(argument) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find(fragment, 1, true) ~= nil)
  end
  bad("bad name", "not a rock name")
  bad("@1.0", "not a rock name")
  bad("plc@", "no constraint")
  bad("plc@=> 1", "unknown constraint operator")
end

function T:test_add_writes_the_constraint_of_the_installed_version_and_keeps_the_comments()
  local files, environment = world(MANIFEST, { plc = "0.5-1" })
  local code, out = run(add, { "add", "plc" }, environment)
  self:assert_equal(0, code)
  self:assert_equal("Added plc ~> 0.5 to dependencies (locked 0.5-1); 1 rock(s) in hecate.lock", out)
  self:assert_equal([[
-- My application.
return {
  name = "app",   -- required
  dependencies = {
    -- (none yet)
    ["plc"] = "~> 0.5",
  },
}
]], files["hecate.project.lua"])
  self:assert_true(files["hecate.lock"]:find("plc = {", 1, true) ~= nil)
end

function T:test_an_explicit_constraint_and_the_dev_flag()
  local files, environment = world(MANIFEST, { plc = "0.5-1" })
  local code = run(add, { "add", "plc@>= 0.5", "--dev" }, environment)
  self:assert_equal(0, code)
  self:assert_true(files["hecate.project.lua"]:find('development_dependencies = {\n    ["plc"] = ">= 0.5",', 1, true) ~= nil, files["hecate.project.lua"])
  local _, json = run(add, { "add", "plc@>= 0.5", "--dev", "--json" }, environment)
  self:assert_equal("json:plc:>= 0.5", json)
end

function T:test_a_failed_install_leaves_the_manifest_and_the_lockfile_untouched()
  local files, environment = world(MANIFEST, {}, true)
  local code, _, err = run(add, { "add", "plc" }, environment)
  self:assert_equal(1, code)
  self:assert_true(err:find("no results matching query", 1, true) ~= nil, err)
  self:assert_equal(MANIFEST, files["hecate.project.lua"])
  self:assert_nil(files["hecate.lock"])
end

function T:test_a_rock_that_is_not_numbered_needs_an_explicit_constraint()
  local files, environment = world(MANIFEST, { plc = "scm-1" })
  local code, _, err = run(add, { "add", "plc" }, environment)
  self:assert_equal(1, code)
  self:assert_true(err:find("choose the constraint yourself", 1, true) ~= nil, err)
  self:assert_equal(MANIFEST, files["hecate.project.lua"])
end

function T:test_a_rock_in_the_other_section_must_be_removed_first()
  local text = 'return {\n  name = "app",\n  dependencies = {\n    ["plc"] = "~> 0.5",\n  },\n}\n'
  local files, environment = world(text, { plc = "0.5-1" })
  local code, _, err = run(add, { "add", "plc", "--dev" }, environment)
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate remove plc", 1, true) ~= nil, err)
  self:assert_equal(text, files["hecate.project.lua"])
end

function T:test_a_manifest_that_cannot_be_edited_safely_is_refused_with_the_line_to_add()
  local one_line = 'return {\n  name = "app",\n  dependencies = { a = "1.0" },\n}\n'
  local files, environment = world(one_line, { plc = "0.5-1" })
  local code, _, err = run(add, { "add", "plc" }, environment)
  self:assert_equal(1, code)
  self:assert_true(err:find('Add this line to the `dependencies` table yourself:', 1, true) ~= nil, err)
  self:assert_true(err:find('["plc"] = ">= 0",', 1, true) ~= nil or err:find('["plc"]', 1, true) ~= nil, err)
  self:assert_equal(one_line, files["hecate.project.lua"])
end

function T:test_usage_errors()
  local _, environment = world(MANIFEST, {})
  local code, _, err = run(add, { "add" }, environment)
  self:assert_equal(2, code)
  self:assert_true(err:find("name one rock", 1, true) ~= nil, err)
  self:assert_equal(2, (run(add, { "add", "a", "b" }, environment)))
  self:assert_equal(2, (run(remove, { "remove" }, environment)))
end

function T:test_remove_deletes_the_line_and_relocks()
  local text = 'return {\n  name = "app",\n  dependencies = {\n    ["plc"] = "~> 0.5",   -- crypto\n    ["luv"] = "~> 1.50",\n  },\n}\n'
  local files, environment = world(text, { plc = "0.5-1", luv = "1.50.0-1" })
  local code, out = run(remove, { "remove", "plc" }, environment)
  self:assert_equal(0, code)
  self:assert_true(out:find("Removed plc from dependencies; 1 rock(s) in hecate.lock", 1, true) ~= nil, out)
  self:assert_equal('return {\n  name = "app",\n  dependencies = {\n    ["luv"] = "~> 1.50",\n  },\n}\n', files["hecate.project.lua"])
  self:assert_true(files["hecate.lock"]:find("plc = {", 1, true) == nil)
  self:assert_true(files["hecate.lock"]:find("luv = {", 1, true) ~= nil)
end

function T:test_remove_names_what_is_wrong()
  local files, environment = world(MANIFEST, {})
  local code, _, err = run(remove, { "remove", "ghost" }, environment)
  self:assert_equal(1, code)
  self:assert_true(err:find("'ghost' is not a dependency", 1, true) ~= nil, err)
  self:assert_equal(MANIFEST, files["hecate.project.lua"])
  local missing, _, err2 = run(remove, { "remove", "x" }, (select(2, world(nil, {}))))
  self:assert_equal(1, missing)
  self:assert_true(err2:find("hecate new", 1, true) ~= nil, err2)
end

return T
