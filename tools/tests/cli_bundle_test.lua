local test = require("harness.test")
local bundle = require("lib.cli_bundle")
local T = test.Case("CliBundleTest")

function T:test_module_names()
  self:assert_equal("hecate.cli.main", bundle.module_name("hecate/cli/main.lua"))
  self:assert_equal("hecate.cli.init", bundle.module_name("hecate/cli/init.lua"))
  self:assert_equal("hecate.cli.commands.init", bundle.module_name("hecate\\cli\\commands\\init.lua"))
end

function T:test_c_bytes_and_strings()
  self:assert_equal("  104,105,", bundle.c_bytes("hi"))
  self:assert_equal(2, select(2, bundle.c_bytes(("x"):rep(17)):gsub("\n", "\n")) + 1)
  self:assert_equal('"a\\"b\\\\c"', bundle.c_string('a"b\\c'))
end

function T:test_render_lists_every_module_and_ends_the_table()
  local c = bundle.render({ { name = "b", source = "return 2" }, { name = "a", source = "x" } })
  self:assert_true(c:find('{ "a", (const char *)module_', 1, true) ~= nil)
  self:assert_true(c:find('{ "b", (const char *)module_', 1, true) ~= nil)
  self:assert_true(c:find("{ 0, 0, 0 }", 1, true) ~= nil)
  self:assert_true(c:find('"a"', 1, true) < c:find('"b"', 1, true))
end

function T:test_collect_serves_the_package_name_of_an_init_file()
  local names = {}
  local source = bundle.collect(".") -- tasks and their tests run from the repository root
  for _, m in ipairs(source) do names[m.name] = true end
  self:assert_true(names["hecate.cli.main"])
  self:assert_true(names["hecate.cli"])
  self:assert_true(names["hecate.cli.commands.init"])
  self:assert_true(names["hecate.core"])
end

-- Builds the executable and runs it; skipped where there is no C compiler or static Lua (the task reports why).
function T:test_built_executable_runs_lua_and_the_cli()
  if package.config:sub(1, 1) == "\\" then return end
  local util = require("lib.util")
  local out = ".hecate/build/cli-test/hecate"
  local log, built = util.capture(("%s tools/run.lua build-cli --output=%s 2>&1"):format(util.quote(util.interpreter()), out))
  if not built and log:find("no Lua 5.5 with", 1, true) then return end -- no static Lua here: nothing to build
  self:assert_true(built, log)
  local version = util.capture(util.quote(out) .. " --lua -e 'io.write(_VERSION)'")
  self:assert_equal("Lua 5.5", version)
  local cli = util.capture(util.quote(out) .. " version")
  self:assert_true(cli:find("^Hecate "), cli)
  local _, ok = util.capture(util.quote(out) .. " --lua -e 'error(1)' 2>/dev/null")
  self:assert_false(ok)
end

return T
