local test = require("harness.test")
local app = require("hecate.cli.app")
local outdated = require("hecate.cli.commands.outdated")
local luarocks = require("hecate.cli.luarocks")
local T = test.Case("CliOutdatedCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", platform = "linux-x86_64" }
local MANIFEST = 'return { name = "app", dependencies = { plc = "~> 0.5", luv = "~> 1.50" }, development_dependencies = { busted = ">= 2.0" } }'

local function run(args, listing, files, rt)
  local dependencies = {
    fs = { read = function(path) return (files or { ["hecate.project.lua"] = MANIFEST })[path] end, write = function() end },
    luarocks = luarocks.new({
      runner = function(_, arguments)
        if listing == false then return { code = 1, stdout = "", stderr = "Error: no network" } end
        assert(arguments[3] == "list" and arguments[4] == "--outdated")
        return { code = 0, stdout = listing or "", stderr = "" }
      end,
      tree = "lua_modules", config_dir = ".hecate/luarocks",
    }),
    run = function(task) return task() end,
  }
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return outdated.execute(context, dependencies) end }, { __index = outdated })
  local code = app.run(args, {
    commands = { command }, runtime = rt or runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value)
      local names = {}
      for _, row in ipairs(value.outdated) do names[#names + 1] = row.name .. ":" .. row.status end
      return "json:" .. table.concat(names, ",")
    end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

local LISTING = table.concat({
  "busted\t2.0.0-1\t2.2.0-1\thttps://luarocks.org",
  "lpeg\t1.0.0-1\t1.1.0-1\thttps://luarocks.org",
  "luv\t1.50.0-1\t1.53.0-0\thttps://luarocks.org",
  "plc\t0.5-1\t0.6-1\thttps://luarocks.org",
}, "\n") .. "\n"

function T:test_each_newer_version_says_what_the_manifest_allows()
  local code, out = run({ "outdated" }, LISTING)
  self:assert_equal(0, code)
  self:assert_true(out:find("busted%s+2.0.0%-1%s+%->%s+2.2.0%-1%s+within >= 2.0") ~= nil, out)   -- a development dependency that fits
  self:assert_true(out:find("lpeg%s+1.0.0%-1%s+%->%s+1.1.0%-1%s+indirect") ~= nil, out)           -- not a dependency of the manifest
  -- `~>` is LuaRocks' prefix match on the components: `~> 1.50` takes 1.50.x only, `~> 0.5` takes 0.5.x only.
  self:assert_true(out:find("luv%s+1.50.0%-1%s+%->%s+1.53.0%-0%s+excluded by ~> 1.50") ~= nil, out)
  self:assert_true(out:find("plc%s+0.5%-1%s+%->%s+0.6%-1%s+excluded by ~> 0.5") ~= nil, out)
end

function T:test_nothing_to_report_and_json()
  local code, out = run({ "outdated" }, "")
  self:assert_equal(0, code)
  self:assert_equal("All rocks are up to date.", out)
  local _, json = run({ "outdated", "--json" }, LISTING)
  self:assert_equal("json:busted:update,lpeg:indirect,luv:constraint,plc:constraint", json)
end

function T:test_failures_name_what_to_do()
  local code, _, err = run({ "outdated" }, false)
  self:assert_equal(1, code)
  self:assert_true(err:find("no network", 1, true) ~= nil, err)
  local missing, _, err2 = run({ "outdated" }, "", {})
  self:assert_equal(1, missing)
  self:assert_true(err2:find("hecate new", 1, true) ~= nil, err2)
  local none = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64" }
  local code3, _, err3 = run({ "outdated" }, "", nil, none)
  self:assert_equal(1, code3)
  self:assert_true(err3:find("LuaRocks was not found", 1, true) ~= nil, err3)
end

return T
