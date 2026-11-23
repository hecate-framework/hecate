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

--- The `tools` directory, found from where `lib.cli_bundle` was loaded (the working directory is not reliable).
local function tools_root()
  local found = package.searchpath("lib.cli_bundle", package.path):gsub("\\", "/")
  return (found:gsub("/lib/cli_bundle%.lua$", ""))
end

function T:test_collect_serves_the_package_name_of_an_init_file()
  local names = {}
  local source = bundle.collect(tools_root() .. "/..")
  local count, found = #source, {}
  for _, m in ipairs(source) do names[m.name] = true found[#found + 1] = m.name end
  table.sort(found)
  local list = table.concat(found, " ", 1, math.min(#found, 12))
  self:assert_true(names["hecate.cli.main"], "missing hecate.cli.main among " .. count .. " modules: " .. list)
  self:assert_true(names["hecate.cli"], "missing hecate.cli among " .. count .. " modules: " .. list)
  self:assert_true(names["hecate.cli.commands.init"], "missing hecate.cli.commands.init among " .. count .. " modules: " .. list)
  self:assert_true(names["hecate.core"], "missing hecate.core among " .. count .. " modules: " .. list)
end

-- Builds the executable and runs it (all platforms); skipped where there is no Lua to link (the task reports why).
function T:test_built_executable_runs_lua_luarocks_and_the_cli()
  local util = require("lib.util")
  local windows = util.is_windows()
  local dir = ".hecate/build/cli-test"
  local out = dir .. "/hecate" .. (windows and ".exe" or "")
  local log, built = util.capture(("%s tools/run.lua build-cli --output=%s 2>&1"):format(util.quote(util.interpreter()), out))
  if not built and log:find("no Lua 5.5 with", 1, true) then return end -- no Lua to link here: nothing to build
  self:assert_true(built, log)
  self:assert_true(not log:find("not linked in", 1, true), log) -- a native module left out: say why
  local exe = util.quote(out)
  -- Run with an empty environment where the shell allows it: the native modules are linked in, so no LUA_CPATH and no
  -- file next to the executable is needed.
  local bare = windows and "" or "env -i "
  local probe = dir .. "/probe.lua"
  local f = assert(io.open(probe, "wb"))
  f:write('io.write(_VERSION, " ", tostring(#require("luv").version_string() > 0), " ", tostring(require("digest") ~= nil), " ",\n',
    '  #require("hecate.json").encode({ 1 }), " ", tostring(require("lfs") ~= nil))\n')
  f:close()
  self:assert_equal("Lua 5.5 true true 3 true", util.capture(bare .. exe .. " --lua " .. util.quote(probe) .. " 2>&1"))
  local cli = util.capture(exe .. " version")
  self:assert_true(cli:find("^Hecate "), cli)
  -- LuaRocks is embedded: `hecate --luarocks` works with no `luarocks` on the path.
  local rocks = util.capture(bare .. exe .. " --luarocks --version 2>&1")
  self:assert_true(rocks:find("3.13", 1, true) ~= nil, rocks)
  -- A script file as the first argument runs as a plain `lua script.lua` (what a rockspec's `$(LUA) script.lua` does).
  self:assert_equal("Lua 5.5 true true 3 true", util.capture(bare .. exe .. " " .. util.quote(probe) .. " 2>&1"))
  local failing = dir .. "/failing.lua"
  f = assert(io.open(failing, "wb"))
  f:write("error('boom')\n")
  f:close()
  local _, ok = util.capture(exe .. " --lua " .. util.quote(failing) .. (windows and " 2>nul" or " 2>/dev/null"))
  self:assert_false(ok)
end

return T
