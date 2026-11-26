local test = require("harness.test")
local main = require("hecate.cli.main")
local T = test.Case("CliMainTest")

function T:test_the_platform_names_the_system_and_the_architecture()
  local platform = main.platform()
  self:assert_true(platform:match("^%l+%-[%w_]+$") ~= nil, platform)
end

function T:test_the_current_directory_is_absolute_with_forward_slashes()
  local directory = main.current_directory() or ""
  self:assert_true(directory ~= "" and directory:find("\\", 1, true) == nil, directory)
  self:assert_true(directory:match("^/") ~= nil or directory:match("^%a:/") ~= nil, directory)
end

function T:test_quoting_keeps_a_path_with_spaces_and_shell_characters_in_one_word()
  self:assert_equal("'/opt/my apps/$HOME/`x`'", main.quote("/opt/my apps/$HOME/`x`", false))
  self:assert_equal("'it'\\''s'", main.quote("it's", false))
  self:assert_equal('"C:\\Program Files\\hecate.exe"', main.quote("C:\\Program Files\\hecate.exe", true))
  self:assert_equal('"a""b"', main.quote('a"b', true))
end

function T:test_a_windows_command_line_that_starts_with_a_quote_is_wrapped_once_more()
  self:assert_equal('""C:\\a b\\h.exe" -v"', main.command_line({ '"C:\\a b\\h.exe"', "-v" }, true))
  self:assert_equal("luarocks --version", main.command_line({ "luarocks", "--version" }, true))
  self:assert_equal("'/a b/h' -v", main.command_line({ "'/a b/h'", "-v" }, false))
end

function T:test_the_version_probes_work_through_a_path_with_a_space_and_a_dollar()
  -- The interpreter running this test, copied under a name that needs quoting.
  local directory = os.tmpname()
  os.remove(directory)
  local lua = arg and arg[-1] or "lua"
  if package.config:sub(1, 1) == "\\" or not os.execute("mkdir -p '" .. directory .. "/my $dir'") then return end
  local link = directory .. "/my $dir/lua"
  if not os.execute("ln -s \"$(command -v '" .. lua .. "')\" '" .. link .. "'") then return end
  local release = main.lua_release(link)
  os.execute("rm -rf '" .. directory .. "'")
  self:assert_equal(_VERSION:match("%d+%.%d+"), release:match("^%d+%.%d+"))
  self:assert_true(release:match("^%d+%.%d+%.%d+$") ~= nil, release)
end

function T:test_the_lua_release_falls_back_to_the_line()
  local line = _VERSION:match("%d+%.%d+")
  self:assert_equal(line, main.lua_release(nil))
  self:assert_equal(line, main.lua_release("/no/such/interpreter"))
  local release = main.lua_release(arg and arg[-1])
  self:assert_equal(line, release:match("^%d+%.%d+"))
end

function T:test_the_runtime_carries_the_interpreter_of_the_executable()
  local runtime = main.runtime({ hecate_version = "9.9.9", lua_interpreter = "/no/such/hecate", lua_interpreter_arguments = { "--lua" } })
  self:assert_equal("9.9.9", runtime.hecate_version)
  self:assert_equal("/no/such/hecate", runtime.lua_interpreter)
  self:assert_equal("--lua", runtime.lua_interpreter_arguments[1])
  self:assert_equal(_VERSION:match("%d+%.%d+"), runtime.lua_version:match("^%d+%.%d+"))
end

return T
