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
  write(self.root .. "/LICENSE", "MIT License\n")
  write(self.root .. "/bin/hecate-elf", "\127ELF pretend dynamic executable")
  self.printed = "Hecate 1.2.3 (Lua 5.5.0) - linux-x86_64"
  self.symbols = read("tools/tests/fixtures/linux_package/objdump_glibc_2_28.txt")
  self.commands = {}
  -- Extraction is real; the executable of the fixture is not a program, so `version` is answered here.
  self.run = function(cmd)
    self.commands[#self.commands + 1] = cmd
    if cmd:find(" version 2>&1", 1, true) then return self.printed, true end
    if cmd:find(" completion ", 1, true) then return "# completion script of " .. cmd:match("completion (%a+)"), true end
    if cmd:find("^objdump ") then return self.symbols, true end
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

function T:test_pre_release_versions_use_the_luarocks_tokens_directly_before_the_revision()
  self:assert_equal("0.4.2rc1", (task.parse_version("0.4.2rc1-1")))
  self:assert_equal("1.0.0beta2", (task.parse_version("1.0.0beta2-3")))
  self:assert_equal("1.0.0alpha10", (task.parse_version("1.0.0alpha10-1")))
  self:assert_equal("1.0.0pre1", (task.parse_version("1.0.0pre1-1")))
  for _, bad in ipairs({ "0.4.2-rc1-1", "0.4.2rc-1", "v0.4.2-1", "0.4.2rc1", "dev-1", "scm-1", "0.4.2dev1-1", "0.4.2scm1-1",
    "0.4.2cvs1-1", "0.4.2RC1-1", "0.4.2rc1.1-1", "0.4.2rc1-1-1", "0.4.2rc1-" }) do
    self:assert_nil((task.parse_version(bad)), bad)
  end
end

function T:test_check_tag_of_a_pre_release_needs_a_version_file_that_holds_it()
  write(self.root .. "/VERSION", "0.4.2rc1\n")
  local ok = task.run({ root = self.root, args = { "--check-tag=0.4.2rc1-1" } })
  self:assert_true(ok.ok, table.concat(ok.problems, "\n"))
  self:assert_equal("0.4.2rc1-1", ok.output)
  self:assert_true(ok.data.prerelease)
  self:assert_equal("true", task.run({ root = self.root, args = { "--check-tag=0.4.2rc1-1", "--prerelease" } }).output)
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=0.4.2-1" } }).ok)
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=0.4.2rc2-1" } }).ok)
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=0.4.2-rc1-1" } }).ok)
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=0.4.2rc1" } }).ok)
  write(self.root .. "/VERSION", "0.4.2\n")
  local final = task.run({ root = self.root, args = { "--check-tag=0.4.2-1", "--prerelease" } })
  self:assert_true(final.ok)
  self:assert_equal("false", final.output)
  self:assert_false(task.run({ root = self.root, args = { "--check-tag=0.4.2rc1-1" } }).ok)
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

function T:test_the_glibc_guard_accepts_the_floor_and_refuses_a_newer_glibc()
  local elf = self.root .. "/bin/hecate-elf"
  local ok = self:package({ "--exe=" .. elf, "--os=linux", "--arch=x86_64", "--no-smoke" })
  self:assert_true(ok.ok, table.concat(ok.problems, "\n"))
  self:assert_equal("2.28", ok.data.glibc.highest)
  self.symbols = read("tools/tests/fixtures/linux_package/objdump_glibc_2_34.txt")
  local refused = self:package({ "--exe=" .. elf, "--os=linux", "--arch=x86_64", "--no-smoke" })
  self:assert_false(refused.ok)
  self:assert_true(refused.problems[1]:find("needs glibc 2.34, above the floor 2.28", 1, true) ~= nil, refused.problems[1])
  self:assert_true(self:package({ "--exe=" .. elf, "--os=linux", "--arch=x86_64", "--no-smoke", "--max-glibc=2.34" }).ok)
  self:assert_true(self:package({ "--exe=" .. elf, "--os=linux", "--arch=x86_64", "--no-smoke", "--max-glibc=none" }).ok)
  -- the guard is for Linux executables only
  self:assert_true(self:package({ "--exe=" .. elf, "--os=darwin", "--arch=aarch64", "--no-smoke" }).ok)
end

function T:test_the_glibc_guard_skips_static_executables_and_files_that_are_not_elf()
  local binary = "\127ELF"
  local run = function() return read("tools/tests/fixtures/linux_package/objdump_static.txt"), false end
  local ok, message = task.check_glibc("hecate", binary, "2.28", run)
  self:assert_true(ok)
  self:assert_true(message:find("skipped", 1, true) ~= nil, message)
  ok, message = task.check_glibc("hecate", "#!/bin/sh", "2.28", function() error("not run") end)
  self:assert_true(ok and message:find("not an ELF", 1, true) ~= nil, message)
  local calls = {}
  ok = task.check_glibc("hecate", binary, "2.28", function(cmd)
    calls[#calls + 1] = cmd:match("^%a+")
    if cmd:find("^objdump") then return "objdump: command not found", false end
    return read("tools/tests/fixtures/linux_package/readelf_glibc_2_34.txt"), true
  end)
  self:assert_false(ok)
  self:assert_equal("objdump readelf", table.concat(calls, " "), "readelf is the fallback")
  ok, message = task.check_glibc("hecate", binary, "2.28", function() return "nothing works", false end)
  self:assert_false(ok)
  self:assert_true(message:find("cannot read the symbol versions", 1, true) ~= nil, message)
end

function T:test_a_deb_is_written_with_its_checksum()
  local _, have_gzip = util.capture("gzip --version")
  if not have_gzip then return end
  local report = self:package({ "--os=linux", "--arch=x86_64", "--format=deb", "--version=1.2.3-2" })
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
  local name = "hecate_1.2.3-2_amd64.deb"
  self:assert_equal(self.root .. "/out/" .. name, report.data.archive)
  self:assert_equal("deb", report.data.format)
  local bytes = assert(read(report.data.archive))
  self:assert_equal(sha256.hex(bytes) .. "  " .. name .. "\n", read(report.data.checksum))
  self:assert_equal("/usr/bin/hecate", report.data.entries[1])
  self:assert_equal(5, #report.data.entries)
  local members = assert(require("lib.linux_package").read_ar(bytes))
  self:assert_equal(3, #members)
  local completions = 0
  for _, command in ipairs(self.commands) do
    if command:find(" completion ", 1, true) then completions = completions + 1 end
  end
  self:assert_equal(3, completions, "bash, zsh and fish are asked of the executable")
end

function T:test_every_package_format_has_its_asset_name()
  local _, have_gzip = util.capture("gzip --version")
  if not have_gzip then return end
  for format, name in pairs({ apk = "hecate-1.2.3_rc1-r2.x86_64.apk" }) do
    write(self.root .. "/VERSION", "1.2.3rc1\n")
    local report = self:package({ "--os=linux", "--arch=x86_64", "--format=" .. format, "--version=1.2.3rc1-2" })
    self:assert_true(report.ok, table.concat(report.problems, "\n"))
    self:assert_equal(self.root .. "/out/" .. name, report.data.archive)
    self:assert_equal(sha256.hex(assert(read(report.data.archive))) .. "  " .. name .. "\n", read(report.data.checksum))
  end
end

function T:test_a_package_needs_linux_x86_64_a_known_format_and_a_working_completion()
  local arm = self:package({ "--os=linux", "--arch=aarch64", "--format=deb" })
  self:assert_false(arm.ok)
  self:assert_true(arm.problems[1]:find("x86_64 only", 1, true) ~= nil, arm.problems[1])
  local mac = self:package({ "--os=darwin", "--arch=aarch64", "--format=deb" })
  self:assert_false(mac.ok)
  self:assert_true(mac.problems[1]:find("for Linux", 1, true) ~= nil, mac.problems[1])
  local unknown = self:package({ "--os=linux", "--arch=x86_64", "--format=msi" })
  self:assert_false(unknown.ok)
  self:assert_true(unknown.problems[1]:find("unknown --format", 1, true) ~= nil, unknown.problems[1])
  self.run = function() return "boom", false end
  local broken = self:package({ "--os=linux", "--arch=x86_64", "--format=apk", "--max-glibc=none" })
  self:assert_false(broken.ok)
  self:assert_true(broken.problems[1]:find("completion bash", 1, true) ~= nil, broken.problems[1])
end

function T:test_the_assets_of_a_release_are_listed_for_the_workflow()
  local report = task.run({ root = self.root, args = { "--list-assets=1.2.3-1" } })
  self:assert_true(report.ok, table.concat(report.problems, "\n"))
  local expected = {
    "hecate-1.2.3-1-darwin-aarch64.tar.gz", "hecate-1.2.3-1-linux-x86_64.tar.gz", "hecate-1.2.3-1-windows-x86_64.zip",
    "hecate-1.2.3-1-x86_64.pkg.tar.zst", "hecate-1.2.3-1.x86_64.rpm", "hecate-1.2.3-r1.x86_64.apk", "hecate_1.2.3-1_amd64.deb",
  }
  local names = {}
  for _, name in ipairs(expected) do
    names[#names + 1] = name
    names[#names + 1] = name .. ".sha256"
  end
  table.sort(names)
  self:assert_equal(14, #report.data.assets)
  self:assert_equal(table.concat(names, "\n"), report.output)
  self:assert_false(task.run({ root = self.root, args = { "--list-assets=1.2.4-1" } }).ok, "must match VERSION")
end

return T
