local test = require("harness.test")
local app = require("hecate.cli.app")
local init = require("hecate.cli.commands.init")
local manifest = require("hecate.cli.manifest")
local T = test.Case("CliInitCommandTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64" }

local function run(args, existing, directory)
  local written = {}
  local present = {}
  for _, path in ipairs(existing or {}) do present[path] = true end
  local dependencies = {
    write = function(path, text) written[path] = text end,
    exists = function(path) return present[path] == true end,
    directory_name = function() return directory or "My Shop" end,
    run = nested.run,
  }
  local command = setmetatable({ run = function(context) return init.execute(context, dependencies) end }, { __index = init })
  local out, err = {}, {}
  local code = app.run(args, {
    commands = { command }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. value.name end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), written
end

function T:test_the_manifest_takes_the_directory_name()
  local code, out, _, written = run({ "init" }, nil, "my-shop")
  self:assert_equal(0, code)
  self:assert_equal("my-shop", manifest.parse(written["hecate.project.lua"]).name)
  self:assert_true(out:find("Initialised my%-shop") ~= nil, out)
end

function T:test_a_name_option_replaces_the_directory_name()
  local _, _, _, written = run({ "init", "--name", "shop" }, nil, "My Shop")
  self:assert_equal("shop", manifest.parse(written["hecate.project.lua"]).name)
end

function T:test_an_unusable_directory_name_is_a_usage_error()
  local code, _, err = run({ "init" })
  self:assert_equal(2, code)
  self:assert_true(err:find("%-%-name") ~= nil, err)
end

function T:test_an_existing_manifest_is_refused()
  local code, _, err, written = run({ "init", "--name", "shop" }, { "hecate.project.lua" })
  self:assert_equal(1, code)
  self:assert_true(err:find("already") ~= nil, err)
  self:assert_equal(nil, next(written))
end

function T:test_existing_files_are_kept()
  local code, _, _, written = run({ "init", "--name", "shop" }, { "main.lua", ".gitignore" })
  self:assert_equal(0, code)
  self:assert_equal(nil, written["main.lua"])
  self:assert_equal(nil, written[".gitignore"])
  self:assert_true(written["hecate.project.lua"] ~= nil)
end

return T
