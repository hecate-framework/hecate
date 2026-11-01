-- Command-line construction of the LuaLS export (pure functions, both platforms) and the temporary
-- directory of an export.
local test = require("harness.test")
local luals = require("hecate.doc.luals")
local core = require("hecate.core")
local doc = require("hecate.doc")
local reactor = require("hecate.reactor")
local T = test.Case("LuaLSTest")

function T:test_posix_quoting_wraps_in_single_quotes_and_escapes_embedded_quotes()
  self:assert_equal("'/a b/c'", luals.quote("/a b/c", false))
  self:assert_equal("'it'\\''s'", luals.quote("it's", false))
  self:assert_equal("'$(rm -rf x) `y` ; & \"z\"'", luals.quote("$(rm -rf x) `y` ; & \"z\"", false))
end

function T:test_windows_quoting_uses_double_quotes_and_backslashes()
  self:assert_equal('"C:\\Program Files\\x"', luals.quote("C:/Program Files/x", true))
  self:assert_equal('"C:\\dir\\\\"', luals.quote("C:\\dir\\", true), "a trailing backslash would escape the closing quote")
  self:assert_equal('"C:\\dir\\\\"', luals.quote("C:/dir/", true))
  self:assert_equal('"a & b ^ c"', luals.quote("a & b ^ c", true), "metacharacters are inert inside the quotes")
end

function T:test_windows_paths_that_cannot_be_quoted_are_refused()
  for _, path in ipairs({ 'a"b', "100%", "a\nb" }) do
    local err = self:assert_error(function() luals.quote(path, true) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), path)
  end
end

function T:test_the_command_line_names_every_option()
  self:assert_equal(
    "'/bin/lls' --doc='/src dir' --doc_out_path='/tmp/x' --logpath='/tmp/x/log' --configpath='/r/.luarc.json'",
    luals.command_line("/bin/lls", "/src dir", "/tmp/x", "/r/.luarc.json", false))
  self:assert_equal("'/bin/lls' --doc='/s' --doc_out_path='/o' --logpath='/o/log'",
    luals.command_line("/bin/lls", "/s", "/o", nil, false))
  self:assert_equal(
    '"C:\\lls\\lls.exe" --doc="C:\\p\\src" --doc_out_path="C:\\t\\x" --logpath="C:\\t\\x\\log" --configpath="C:\\p\\.luarc.json"',
    luals.command_line("C:/lls/lls.exe", "C:/p/src", "C:/t/x", "C:/p/.luarc.json", true))
end

function T:test_export_rejects_invalid_arguments()
  ---@diagnostic disable-next-line: param-type-mismatch  -- the argument is invalid on purpose
  local err = self:assert_error(function() luals.export(3, "s", {}) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_a_failed_export_leaves_no_temporary_directory_and_uses_an_unpredictable_one()
  if package.config:sub(1, 1) == "\\" then return end
  local removed, errors, left = {}, {}, {}
  reactor.run(function()
    local fs = doc.SystemFileSystem()
    local spy = setmetatable({ remove_tree = function(_, path) removed[#removed + 1] = path; fs:remove_tree(path) end },
      { __index = fs })
    for index = 1, 2 do
      local ok, err = pcall(luals.export, "/nonexistent/lua-language-server", "/nonexistent/src", { fs = spy })
      errors[index] = ok and "no error" or err
    end
    for _, path in ipairs(removed) do left[#left + 1] = fs:exists(path) end
  end)
  for _, err in ipairs(errors) do self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err)) end
  self:assert_equal(2, #removed)
  self:assert_true(removed[1] ~= removed[2], "two exports use two directories")
  for index, path in ipairs(removed) do
    self:assert_true(path:find("hecate%-luals%.%w%w%w%w%w%w%w%w%w%w$") ~= nil, path)
    self:assert_false(left[index], path .. " was left behind")
  end
end

return T
