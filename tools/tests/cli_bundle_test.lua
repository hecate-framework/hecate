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
  -- Non-ASCII paths (OQ-147): a script in a directory with a non-ASCII name is created, passed as an argument and run
  -- by a child process, all by the executable (the test's own Lua may not be UTF-8 aware on Windows).
  local unicode = dir .. "/unicode.lua"
  f = assert(io.open(unicode, "wb"))
  f:write([[
local lfs, luv = require("lfs"), require("luv")
local directory = arg[1] .. "/caf\xC3\xA9-\xE6\x9D\x8E"
lfs.mkdir(directory)
local script = directory .. "/child.lua"
local child = assert(io.open(script, "wb"))
child:write('assert(io.open(arg[0] .. ".ok", "wb")):close()')
child:close()
local code
luv.spawn(arg[-1], { args = { script } }, function(status) code = status end)
luv.run()
local marker = io.open(script .. ".ok", "rb")
io.write(tostring(code), " ", tostring(marker ~= nil))
]])
  f:close()
  self:assert_equal("0 true", util.capture(exe .. " " .. util.quote(unicode) .. " " .. util.quote(dir) .. " 2>&1"))
  local failing = dir .. "/failing.lua"
  f = assert(io.open(failing, "wb"))
  f:write("error('boom')\n")
  f:close()
  local _, ok = util.capture(exe .. " --lua " .. util.quote(failing) .. (windows and " 2>nul" or " 2>/dev/null"))
  self:assert_false(ok)
end

-- The host under AddressSanitizer and UndefinedBehaviorSanitizer (Unix): many arguments, error paths, a missing
-- module and the embedded LuaRocks. Skipped where the compiler has no sanitizer runtime.
function T:test_sanitized_host_survives_hard_inputs()
  local util = require("lib.util")
  if util.is_windows() then return end
  local dir = ".hecate/build/cli-sanitize"
  local out = dir .. "/hecate"
  local log, built = util.capture(("%s tools/run.lua build-cli --sanitize --output=%s 2>&1"):format(util.quote(util.interpreter()), out))
  if not built and (log:find("no Lua 5.5 with", 1, true) or log:find("sanitize", 1, true) and log:find("cannot find", 1, true)) then return end
  self:assert_true(built, log)
  local exe = "ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 " .. util.quote(out)
  local script = dir .. "/hard.lua"
  local f = assert(io.open(script, "wb"))
  f:write('io.write(select("#", ...), " ", #arg, " ", tostring(pcall(require, "no.such.module")))\n')
  f:close()
  local words = {}
  for i = 1, 3000 do words[i] = tostring(i) end
  self:assert_equal("3000 3000 false", util.capture(exe .. " " .. util.quote(script) .. " " .. table.concat(words, " ") .. " 2>&1"))
  local failing = dir .. "/failing.lua"
  f = assert(io.open(failing, "wb"))
  f:write("error({ })\n")
  f:close()
  local message, ok = util.capture(exe .. " " .. util.quote(failing) .. " 2>&1")
  self:assert_false(ok)
  self:assert_true(message:find("error object is a table value", 1, true) ~= nil, message)
  local rocks = util.capture(exe .. " --luarocks --version 2>&1")
  self:assert_true(rocks:find("3.13", 1, true) ~= nil, rocks)
  self:assert_true(util.capture(exe .. " version 2>&1"):find("^Hecate ") ~= nil)
  self:assert_false(select(2, util.capture(exe .. " --lua -e 2>&1")))
  self:assert_false(select(2, util.capture(exe .. " --lua --bogus 2>&1")))
end

return T
