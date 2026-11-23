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
