local test = require("harness.test")
local app = require("hecate.cli.app")
local parser = require("hecate.cli.parser")
local version = require("hecate.cli.commands.version")
local T = test.Case("CliAppTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", platform = "linux-x86_64" }

local function run(args, commands)
  local out, err = {}, {}
  local code = app.run(args, {
    commands = commands or { version },
    runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. value.hecate .. ":" .. value.platform end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

function T:test_version_prints_the_versions_and_the_platform()
  local code, out = run({ "version" })
  self:assert_equal(0, code)
  self:assert_equal("Hecate 0.1.0 (Lua 5.5.1, LuaRocks 3.13.0) — linux-x86_64", out)
end

function T:test_the_version_flag_is_the_version_command()
  local code, out = run({ "--version" })
  self:assert_equal(0, code)
  self:assert_equal("Hecate 0.1.0 (Lua 5.5.1, LuaRocks 3.13.0) — linux-x86_64", out)
  local _, json = run({ "--version", "--json" })
  self:assert_equal("json:0.1.0:linux-x86_64", json)
  -- Only without a command: `version --version` is an unknown option, like any other.
  local code_option = run({ "version", "--version" })
  self:assert_equal(2, code_option)
end

function T:test_json_flag_switches_to_machine_readable_output()
  local code, out = run({ "version", "--json" })
  self:assert_equal(0, code)
  self:assert_equal("json:0.1.0:linux-x86_64", out)
  local _, out_before = run({ "--json", "version" })
  self:assert_equal(out, out_before)
end

function T:test_help_lists_commands_and_exits_zero()
  local code, out = run({ "--help" })
  self:assert_equal(0, code)
  self:assert_true(out:find("version", 1, true) ~= nil)
  local code_command, out_command = run({ "version", "--help" })
  self:assert_equal(0, code_command)
  self:assert_true(out_command:find("Usage: hecate version", 1, true) ~= nil)
end

function T:test_hidden_commands_are_not_listed_and_complete_runs_through_the_app()
  local completion_commands = require("hecate.cli.commands.completion")
  local commands = { version, completion_commands[1], completion_commands[2] }
  local _, help = run({ "--help" }, commands)
  self:assert_true(help:find("__complete", 1, true) == nil)
  self:assert_true(help:find("completion", 1, true) ~= nil)
  local code, out = run({ "__complete", "--", "ver" }, commands)
  self:assert_equal(0, code)
  self:assert_equal("version", out)
  local _, flags = run({ "__complete", "--", "completion", "--" }, commands)
  self:assert_equal("--help\n--json", flags)
end

function T:test_no_command_prints_help_and_exits_with_usage_code()
  local code, out = run({})
  self:assert_equal(2, code)
  self:assert_true(out:find("Usage: hecate <command>", 1, true) ~= nil)
end

function T:test_unknown_command_and_option_are_usage_errors_with_a_hint()
  local code, _, err = run({ "frobnicate" })
  self:assert_equal(2, code)
  self:assert_true(err:find("unknown command 'frobnicate'", 1, true) ~= nil)
  self:assert_true(err:find("hecate --help", 1, true) ~= nil)
  local code_option, _, err_option = run({ "version", "--bogus" })
  self:assert_equal(2, code_option)
  self:assert_true(err_option:find("unknown option --bogus", 1, true) ~= nil)
end

function T:test_a_raised_error_is_a_failure_exit_code_with_the_message()
  local failing = { name = "boom", summary = "fails", run = function() error("kaput", 0) end }
  local code, _, err = run({ "boom" }, { failing })
  self:assert_equal(1, code)
  self:assert_equal("hecate boom: kaput", err)
end

function T:test_a_command_returns_its_own_exit_code()
  local code = run({ "three" }, { { name = "three", summary = "x", run = function() return 3 end } })
  self:assert_equal(3, code)
end

local watch = {
  name = "serve",
  summary = "x",
  options = {
    { name = "watch", summary = "reload" },
    { name = "workers", takes_value = true, summary = "n" },
    { name = "tag", takes_value = true, repeatable = true, summary = "t" },
  },
  run = function() end,
}

function T:test_options_flags_values_and_positionals()
  local parsed = parser.parse({ "serve", "--watch", "--workers=4", "--tag", "a", "--tag=b", "app.lua", "--", "--x" }, { watch })
  self:assert_true(parsed.options.watch)
  self:assert_equal("4", parsed.options.workers)
  self:assert_equal("a,b", table.concat(parsed.options.tag --[[@as string[] ]], ","))
  self:assert_equal("app.lua,--x", table.concat(parsed.positionals, ","))
end

function T:test_option_errors()
  local function fails(args, fragment)
    local err = self:assert_error(function() parser.parse(args, { watch }) end)
    self:assert_true(tostring(err.message):find(fragment, 1, true) ~= nil, tostring(err.message))
  end
  fails({ "serve", "--workers" }, "needs a value")
  fails({ "serve", "--workers=1", "--workers=2" }, "given twice")
  fails({ "serve", "--watch=yes" }, "takes no value")
end

function T:test_two_word_commands_win_over_one_word_commands()
  local install = { name = "toolchain install", summary = "x", run = function() end }
  local plain = { name = "toolchain", summary = "x", run = function() end }
  local parsed = parser.parse({ "toolchain", "install", "5.5" }, { plain, install })
  self:assert_equal("toolchain install", parsed.command.name)
  self:assert_equal("5.5", parsed.positionals[1])
  self:assert_equal("toolchain", parser.parse({ "toolchain" }, { plain, install }).command.name)
end

return T
