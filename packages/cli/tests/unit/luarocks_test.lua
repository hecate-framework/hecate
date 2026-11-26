local test = require("harness.test")
local core = require("hecate.core")
local luarocks = require("hecate.cli.luarocks")
local T = test.Case("CliLuaRocksTest")

--- A runner that records the calls and answers from a script of results (a function of the arguments).
local function fake(answer)
  local calls = {}
  local function runner(program, args, options)
    calls[#calls + 1] = { program = program, args = args, options = options }
    return answer(args, #calls)
  end
  return runner, calls
end

local function new(runner)
  ---@diagnostic disable-next-line: return-type-mismatch
  return luarocks.new({ runner = runner, tree = "lua_modules", config_dir = ".hecate/luarocks/" })
end

local LISTING = "plc\t0.5-1\tinstalled\t/x\nhecate-core\t0.1.0-1\tinstalled\t/x\n"

function T:test_configuration_names_the_tree_and_nothing_else()
  local text = luarocks.new({ runner = function() return { code = 0, stdout = "", stderr = "" } end, tree = "lua_modules", config_dir = "c", rocks_servers = { "https://a.test" },
    variables = { LUA_LIBDIR = "C:\\lua\\lib", LUALIB = "lua55.lib" } }):config_text()
  self:assert_true(text:find('{ name = "project", root = "lua_modules" }', 1, true) ~= nil)
  self:assert_true(text:find('rocks_servers = { "https://a.test" }', 1, true) ~= nil)
  self:assert_true(text:find('LUA_LIBDIR = "C:\\\\lua\\\\lib",', 1, true) ~= nil)
  self:assert_true(text:find('LUALIB = "lua55.lib",', 1, true) ~= nil)
  self:assert_true(text:find("https://luarocks.org", 1, true) == nil)
  local defaults = new(function() return { code = 0, stdout = "", stderr = "" } end):config_text()
  self:assert_true(defaults:find('rocks_servers = { "https://luarocks.org" }', 1, true) ~= nil)
end

function T:test_the_environment_replaces_the_user_and_system_configuration()
  local path, env = new(function() return { code = 0, stdout = "", stderr = "" } end):environment()
  self:assert_equal(".hecate/luarocks/config.lua", path)
  self:assert_equal(path, env.LUAROCKS_CONFIG_5_5)
  self:assert_equal(".hecate/luarocks/system", env.LUAROCKS_SYSCONFDIR)
end

function T:test_every_command_has_an_explicit_tree_and_the_isolated_environment()
  local runner, calls = fake(function() return { code = 0, stdout = LISTING, stderr = "" } end)
  local installed = new(runner):installed()
  self:assert_equal("luarocks", calls[1].program)
  self:assert_equal("--tree lua_modules list --porcelain", table.concat(calls[1].args, " "))
  self:assert_equal(".hecate/luarocks/config.lua", calls[1].options.env.LUAROCKS_CONFIG_5_5)
  self:assert_equal("hecate-core,plc", installed[1].name .. "," .. installed[2].name)
  self:assert_equal("0.5-1", installed[2].version)
end

function T:test_outdated_rocks_come_from_the_porcelain_listing()
  local runner, calls = fake(function()
    return { code = 0, stdout = "luv\t1.50.0-1\t1.53.0-1\thttps://luarocks.org\nplc\t0.5-1\t0.6-1\thttps://luarocks.org\n", stderr = "" }
  end)
  local outdated = new(runner):outdated()
  self:assert_equal("--tree lua_modules list --outdated --porcelain", table.concat(calls[1].args, " "))
  self:assert_equal(2, #outdated)
  self:assert_equal("luv 1.50.0-1 1.53.0-1 https://luarocks.org", table.concat({ outdated[1].name, outdated[1].installed, outdated[1].available, outdated[1].server }, " "))
  self:assert_equal("plc", outdated[2].name)
  local none = new(fake(function() return { code = 0, stdout = "", stderr = "" } end)):outdated()
  self:assert_equal(0, #none)
  local failing = fake(function() return { code = 1, stdout = "", stderr = "Error: no network" } end)
  local err = self:assert_error(function() new(failing):outdated() end)
  self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find("no network", 1, true) ~= nil)
end

function T:test_install_judges_success_by_the_installed_set_not_the_exit_status()
  -- LuaRocks may exit 1 although everything is installed (spike OQ-2).
  local runner, calls = fake(function(args)
    if args[3] == "install" then return { code = 1, stdout = "", stderr = "pinned noise" } end
    return { code = 0, stdout = LISTING, stderr = "" }
  end)
  local installed = new(runner):install_dependencies(".hecate/project.rockspec", { "plc", "hecate-core" })
  self:assert_equal(2, #installed)
  self:assert_equal("--tree lua_modules install --deps-only .hecate/project.rockspec", table.concat(calls[1].args, " "))

  local failing = fake(function(args)
    if args[3] == "install" then return { code = 0, stdout = "", stderr = "" } end
    return { code = 0, stdout = "plc\t0.5-1\tinstalled\t/x\n", stderr = "" }
  end)
  local err = self:assert_error(function() new(failing):install_dependencies("r", { "plc", "ghost", "alpha" }) end)
  self:assert_true(core.is_instance_of(err, core.StateError), tostring(err))
  self:assert_equal("alpha,ghost", table.concat(err.context.missing, ","))
end

function T:test_a_failed_install_reports_what_luarocks_said()
  local runner = fake(function(args)
    if args[3] == "install" then return { code = 1, stdout = "", stderr = "Error: no results matching query" } end
    return { code = 0, stdout = "", stderr = "" }
  end)
  local err = self:assert_error(function() new(runner):install_dependencies("r", { "ghost" }) end)
  self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find("no results matching query", 1, true) ~= nil)
end

function T:test_pin_runs_in_the_work_directory_and_a_failure_is_an_error()
  local runner, calls = fake(function() return { code = 0, stdout = "", stderr = "" } end)
  new(runner):pin(".hecate/project.rockspec", ".hecate")
  self:assert_equal("--tree lua_modules build --pin --only-deps .hecate/project.rockspec", table.concat(calls[1].args, " "))
  self:assert_equal(".hecate", calls[1].options.cwd)
  local failing = fake(function() return { code = 1, stdout = "", stderr = "Could not satisfy dependency" } end)
  local err = self:assert_error(function() new(failing):pin("r", "w") end)
  self:assert_true(tostring((err --[[@as hecate.core.Error]]).message):find("Could not satisfy", 1, true) ~= nil)
end

function T:test_an_exact_rockspec_pins_every_locked_rock_including_transitive_ones()
  local text = luarocks.rockspec_text({
    name = "acme-api", version = "0.1.0", dependencies = { hecate = "~> 0.3" },
  }, { hecate = "0.3.2-1", luv = "1.53.0-1" })
  self:assert_true(text:find('"hecate == 0.3.2-1",', 1, true) ~= nil, text)
  self:assert_true(text:find('"luv == 1.53.0-1",', 1, true) ~= nil, text)
  self:assert_true(text:find("~>", 1, true) == nil, text)
end

function T:test_the_rockspec_stands_for_the_manifest()
  local text = luarocks.rockspec_text({
    name = "acme-api", version = "0.1.0", lua = "5.5",
    dependencies = { hecate = "~> 0.3", ["hecate-postgresql"] = "~> 0.3" },
    development_dependencies = { ["hecate-test"] = "~> 0.3", hecate = "~> 0.3" },
  })
  self:assert_true(text:find('package = "acme-api"', 1, true) ~= nil)
  self:assert_true(text:find('version = "0.1.0-1"', 1, true) ~= nil)
  self:assert_true(text:find('"lua >= 5.5, < 5.6",', 1, true) ~= nil)
  self:assert_true(text:find('"hecate ~> 0.3",', 1, true) ~= nil)
  self:assert_true(text:find('"hecate-test ~> 0.3",', 1, true) ~= nil)
  local _, count = text:gsub('"hecate ~> 0.3"', "")
  self:assert_equal(1, count)
  -- Valid Lua that returns nothing but sets the fields.
  local env = {}
  assert(load(text, "=rockspec", "t", env))()
  self:assert_equal("3.0", env.rockspec_format)
  self:assert_equal(4, #env.dependencies)
  self:assert_equal("none", env.build.type)
end

function T:test_the_rockspec_file_name_has_the_shape_luarocks_requires()
  self:assert_equal("acme-api-0.1.0-1.rockspec", luarocks.rockspec_file_name({ name = "acme-api", version = "0.1.0" }))
  self:assert_equal("x-0.0.0-1.rockspec", luarocks.rockspec_file_name({ name = "x" }))
end

function T:test_the_lua_line_after_the_supported_one()
  self:assert_equal("5.6", luarocks.next_lua_line("5.5"))
  self:assert_equal("5.5", luarocks.next_lua_line("5.4"))
  self:assert_error(function() luarocks.next_lua_line("five") end)
end

function T:test_the_lock_is_read_without_the_lua_pseudo_rock()
  local pins = luarocks.parse_lock('return { dependencies = { lua = "5.5-1", plc = "0.5-1", ["hecate-core"] = "0.1.0-1" } }')
  self:assert_equal("0.5-1", pins.plc)
  self:assert_equal("0.1.0-1", pins["hecate-core"])
  self:assert_nil(pins.lua)
  local function bad(text)
    local err = self:assert_error(function() luarocks.parse_lock(text) end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  end
  bad("return {")
  bad("return 3")
  bad("return { dependencies = { a = 1 } }")
  bad('return { dependencies = { a = require("x") } }')
end

function T:test_required_options()
  local runner = function() return { code = 0, stdout = "", stderr = "" } end
  ---@diagnostic disable-next-line: missing-fields
  self:assert_error(function() luarocks.new({ tree = "t", config_dir = "c" }) end)
  ---@diagnostic disable-next-line: missing-fields
  self:assert_error(function() luarocks.new({ runner = runner, config_dir = "c" }) end)
  ---@diagnostic disable-next-line: missing-fields
  self:assert_error(function() luarocks.new({ runner = runner, tree = "t" }) end)
end

function T:test_the_executable_runs_luarocks_with_itself_as_the_lua_interpreter()
  local runner, calls = fake(function() return { code = 0, stdout = "", stderr = "" } end)
  ---@diagnostic disable-next-line: return-type-mismatch
  local rocks = luarocks.new({ runner = runner, tree = "lua_modules", config_dir = "c", program = "/bin/hecate", program_arguments = { "--luarocks" } })
  rocks:run({ "list" })
  self:assert_equal("/bin/hecate", calls[1].program)
  self:assert_equal("--luarocks LUA=/bin/hecate --tree lua_modules list", table.concat(calls[1].args, " "))
end

return T
