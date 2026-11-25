local test = require("harness.test")
local util = require("lib.util")
local sha256 = require("lib.sha256")
local archive = require("lib.archive")
local task = require("tasks.package_cli")
local T = test.Case("PackageCliTest")

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

function T:set_up()
  self.root = assert(util.make_temp_dir(".hecate/tmp", "package-cli-test"))
  write(self.root .. "/VERSION", "1.2.3\n")
  util.mkdir(self.root .. "/bin")
  write(self.root .. "/bin/hecate", "pretend executable")
  write(self.root .. "/bin/hecate.exe", "pretend executable")
  write(self.root .. "/bin/lua55.dll", "pretend dll")
  self.printed = "Hecate 1.2.3 (Lua 5.5.0) - linux-x86_64"
  -- Extraction is real; the executable of the fixture is not a program, so `version` is answered here.
  self.run = function(cmd)
    if cmd:find(" version 2>&1", 1, true) then return self.printed, true end
    return util.capture(cmd)
  end
end

function T:tear_down() util.remove_tree(self.root) end

function T:package(args, ...)
  local all = { "--exe=" .. self.root .. "/bin/hecate", "--out=" .. self.root .. "/out" }
  for _, a in ipairs(args or {}) do all[#all + 1] = a end
  return task.run({ root = self.root, args = all, run = self.run })
end

function T:test_names_follow_the_asset_convention()
  self:assert_equal("hecate-0.1.0-1-linux-x86_64.tar.gz", task.archive_name("0.1.0-1", "linux", "x86_64"))
  self:assert_equal("hecate-0.1.0-2-darwin-aarch64.tar.gz", task.archive_name("0.1.0-2", "darwin", "aarch64"))
  self:assert_equal("hecate-0.1.0-1-windows-x86_64.zip", task.archive_name("0.1.0-1", "windows", "x86_64"))
end

function T:test_os_and_arch_are_derived_from_uname_and_the_windows_environment()
  self:assert_equal("linux", task.host_os("Linux", false))
  self:assert_equal("darwin", task.host_os("Darwin", false))
  self:assert_equal("windows", task.host_os("MINGW64_NT", true))
  self:assert_nil(task.host_os("FreeBSD", false))
  self:assert_equal("x86_64", task.host_arch("x86_64"))
  self:assert_equal("x86_64", task.host_arch("AMD64"))
  self:assert_equal("aarch64", task.host_arch("arm64"))
  self:assert_equal("aarch64", task.host_arch("aarch64"))
  self:assert_nil(task.host_arch("riscv64"))
end

function T:test_versions_are_x_y_z_dash_revision_without_a_v_prefix()
  self:assert_equal("0.1.0", (task.parse_version("0.1.0-1")))
  self:assert_equal("12", select(2, task.parse_version("1.2.3-12")))
  self:assert_nil((task.parse_version("v0.1.0-1")))
  self:assert_nil((task.parse_version("0.1.0")))
  self:assert_nil((task.parse_version("0.1-1")))
  self:assert_nil((task.parse_version("0.1.0-1-rc1")))
end

function T:test_check_tag_accepts_the_version_of_the_file_and_rejects_others()
  local ok = task.run({ root = self.root, args = { "--check-tag=1.2.3-4" } })
  self:assert_true(ok.ok)
  self:assert_equal("1.2.3-4", ok.output)
  local other = task.run({ root = self.root, args = { "--check-tag=1.2.4-1" } })
  self:assert_false(other.ok)
  self:assert_true(other.problems[1]:find("does not match the VERSION file", 1, true) ~= nil, other.problems[1])
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=v1.2.3-1" } }).ok)
end

function T:test_a_tar_gz_is_written_with_its_checksum_and_passes_the_smoke_check()
  local _, have_gzip = util.capture("gzip --version")
  if not have_gzip then return end
  local report = self:package({ "--os=linux", "--arch=x86_64", "--version=1.2.3-2" })
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
  local name = "hecate-1.2.3-2-linux-x86_64.tar.gz"
  self:assert_equal(self.root .. "/out/" .. name, report.data.archive)
  self:assert_equal("passed", report.data.smoke)
  local bytes = assert(read(report.data.archive))
  local line = assert(read(report.data.checksum))
  self:assert_equal(sha256.hex(bytes) .. "  " .. name .. "\n", line)
  self:assert_equal(report.data.sha256, sha256.hex(bytes))
  self:assert_nil(read(report.data.archive .. ".tar.tmp"), "the intermediate tar is removed")
end

function T:test_the_same_input_gives_the_same_bytes()
  local _, have_gzip = util.capture("gzip --version")
  if not have_gzip then return end
  local first = self:package({ "--os=linux", "--arch=x86_64", "--no-smoke" })
  local before = read(first.data.archive)
  local second = self:package({ "--os=linux", "--arch=x86_64", "--no-smoke" })
  self:assert_true(before == read(second.data.archive))
  self:assert_equal("skipped", second.data.smoke)
end

function T:test_a_zip_holds_the_executable_and_the_dll_at_its_root()
  local report = self:package({ "--os=windows", "--arch=aarch64", "--exe=" .. self.root .. "/bin/hecate.exe", "--no-smoke" })
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
  self:assert_equal("hecate-1.2.3-1-windows-aarch64.zip", report.data.archive:match("[^/]+$"))
  local entries = assert(archive.read_zip(assert(read(report.data.archive))))
  self:assert_equal("hecate.exe", entries[1].name)
  self:assert_equal("lua55.dll", entries[2].name)
  self:assert_equal("pretend dll", entries[2].data)
end

function T:test_the_windows_archive_needs_the_dll_beside_the_executable()
  os.remove(self.root .. "/bin/lua55.dll")
  local report = self:package({ "--os=windows", "--arch=x86_64", "--exe=" .. self.root .. "/bin/hecate.exe", "--no-smoke" })
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("lua55.dll", 1, true) ~= nil)
end

function T:test_the_smoke_check_fails_on_another_version()
  local _, have_gzip = util.capture("gzip --version")
  if not have_gzip then return end
  self.printed = "Hecate 9.9.9 (Lua 5.5.0)"
  local report = self:package({ "--os=linux", "--arch=x86_64" })
  self:assert_false(report.ok)
  self:assert_equal("failed", report.data.smoke)
  self:assert_true(report.problems[1]:find("Hecate 1.2.3", 1, true) ~= nil, report.problems[1])
end

function T:test_a_missing_executable_and_a_bad_argument_are_reported()
  local missing = task.run({ root = self.root, args = { "--exe=" .. self.root .. "/none", "--os=linux", "--arch=x86_64" } })
  self:assert_false(missing.ok)
  self:assert_true(missing.problems[1]:find("build-cli", 1, true) ~= nil)
  self:assert_false(task.run({ root = self.root, args = { "--bogus" } }).ok)
  self:assert_false(self:package({ "--os=plan9" }).ok)
  self:assert_false(self:package({ "--arch=riscv64", "--os=linux" }).ok)
end

return T
