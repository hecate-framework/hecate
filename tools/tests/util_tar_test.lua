local test = require("harness.test")
local util = require("lib.util")
local T = test.Case("UtilTarTest")

-- Git for Windows ships a GNU tar that comes first on PATH on the CI runners; it misreads `D:` as a remote host and
-- cannot read a zip. The helper names the system's own bsdtar there and the plain `tar` everywhere else.
function T:test_tar_is_plain_off_windows()
  self:assert_equal("tar", util.tar_command(false))
  self:assert_equal("tar", util.tar_command(false, "C:\\Windows"))
end

function T:test_tar_is_the_system_one_on_windows()
  self:assert_equal('"C:\\Windows\\System32\\tar.exe"', util.tar_command(true, "C:\\Windows"))
  self:assert_equal('"D:\\Win Dir\\System32\\tar.exe"', util.tar_command(true, "D:\\Win Dir"))
end

function T:test_a_quote_in_the_system_root_is_doubled_not_left_to_end_the_argument()
  self:assert_equal('"C:\\a""b\\System32\\tar.exe"', util.tar_command(true, 'C:\\a"b'))
end

function T:test_the_running_platform_is_the_default()
  local expected = util.is_windows() and '"C:\\Windows\\System32\\tar.exe"' or "tar"
  local root = os.getenv("SystemRoot") or "C:\\Windows"
  if util.is_windows() then expected = '"' .. root .. '\\System32\\tar.exe"' end
  self:assert_equal(expected, util.tar_command())
end

return T
