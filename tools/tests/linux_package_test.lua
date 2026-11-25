local test = require("harness.test")
local util = require("lib.util")
local archive = require("lib.archive")
local md5 = require("lib.md5")
local linux_package = require("lib.linux_package")
local T = test.Case("LinuxPackageTest")

local FIXTURES = "tools/tests/fixtures/linux_package/"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

local function have(command) return select(2, util.capture(command .. " >/dev/null 2>&1")) end

function T:set_up()
  self.dir = assert(util.make_temp_dir(".hecate/tmp", "linux-package-test"))
  self.versions = assert(linux_package.versions("0.4.2rc1-3"))
  self.files = linux_package.files("deb", {
    executable = ("binary\0bytes"):rep(500), license = "MIT License\n\nCopyright (c) 2026\n",
    completions = { bash = "complete -F _hecate hecate\n", zsh = "#compdef hecate\n", fish = "complete -c hecate\n" },
  })
end

function T:tear_down() util.remove_tree(self.dir) end

function T:test_md5_matches_the_rfc_1321_vectors()
  self:assert_equal("d41d8cd98f00b204e9800998ecf8427e", md5.hex(""))
  self:assert_equal("900150983cd24fb0d6963f7d28e17f72", md5.hex("abc"))
  self:assert_equal("f96b697d7cb7938d525a2f31aaf161d0", md5.hex("message digest"))
  self:assert_equal("57edf4a22be3c955ac49da2e2107b67a", md5.hex(("1234567890"):rep(8)))
  self:assert_equal("cabe45dcc9ae5b66ba86600cca6b8ba8", md5.hex(("a"):rep(1000)))
end

function T:test_a_release_version_maps_to_the_syntax_of_each_format()
  local v = self.versions
  self:assert_equal("0.4.2~rc1-3", v.deb)
  self:assert_equal("0.4.2~rc1", v.rpm_version)
  self:assert_equal("3", v.rpm_release)
  self:assert_equal("0.4.2rc1", v.arch_version)
  self:assert_equal("3", v.arch_release)
  self:assert_equal("0.4.2_rc1-r3", v.apk)
  local final = assert(linux_package.versions("1.0.0-1"))
  self:assert_equal("1.0.0-1", final.deb)
  self:assert_equal("1.0.0", final.rpm_version)
  self:assert_equal("1.0.0", final.arch_version)
  self:assert_equal("1.0.0-r1", final.apk)
  for token, tilde in pairs({ alpha = "~alpha2", beta = "~beta2", pre = "~pre2", rc = "~rc2" }) do
    local m = assert(linux_package.versions("2.3.4" .. token .. "2-7"))
    self:assert_equal("2.3.4" .. tilde .. "-7", m.deb)
    self:assert_equal("2.3.4_" .. token .. "2-r7", m.apk)
    self:assert_equal("2.3.4" .. token .. "2", m.arch_version)
  end
  self:assert_nil((linux_package.versions("v1.0.0-1")))
  self:assert_nil((linux_package.versions("1.0.0")))
end

function T:test_asset_names_follow_the_convention()
  local v = self.versions
  self:assert_equal("hecate_0.4.2~rc1-3_amd64.deb", linux_package.asset_name("deb", v))
  self:assert_equal("hecate-0.4.2~rc1-3.x86_64.rpm", linux_package.asset_name("rpm", v))
  self:assert_equal("hecate-0.4.2rc1-3-x86_64.pkg.tar.zst", linux_package.asset_name("archlinux", v))
  self:assert_equal("hecate-0.4.2_rc1-r3.x86_64.apk", linux_package.asset_name("apk", v))
  local final = assert(linux_package.versions("0.1.0-1"))
  self:assert_equal("hecate_0.1.0-1_amd64.deb", linux_package.asset_name("deb", final))
  self:assert_equal("hecate-0.1.0-1.x86_64.rpm", linux_package.asset_name("rpm", final))
  self:assert_equal("hecate-0.1.0-1-x86_64.pkg.tar.zst", linux_package.asset_name("archlinux", final))
  self:assert_equal("hecate-0.1.0-r1.x86_64.apk", linux_package.asset_name("apk", final))
  self:assert_error(function() linux_package.asset_name("msi", v) end, "unknown format")
end

function T:test_versions_compare_as_numbers()
  self:assert_equal(-1, linux_package.compare_versions("2.9", "2.28"))
  self:assert_equal(1, linux_package.compare_versions("2.34", "2.28"))
  self:assert_equal(0, linux_package.compare_versions("2.28", "2.28.0"))
  self:assert_equal(-1, linux_package.compare_versions("2.2.5", "2.14"))
end

function T:test_the_highest_glibc_version_is_read_from_objdump_and_readelf_text()
  self:assert_equal("2.28", linux_package.highest_glibc(assert(read(FIXTURES .. "objdump_glibc_2_28.txt"))))
  self:assert_equal("2.34", linux_package.highest_glibc(assert(read(FIXTURES .. "objdump_glibc_2_34.txt"))))
  self:assert_equal("2.34", linux_package.highest_glibc(assert(read(FIXTURES .. "readelf_glibc_2_34.txt"))))
  self:assert_nil(linux_package.highest_glibc(assert(read(FIXTURES .. "objdump_static.txt"))))
  self:assert_nil(linux_package.highest_glibc(""))
  self:assert_equal("2.2.5", linux_package.highest_glibc("memcpy@GLIBC_2.2.5 (2)\n"))
end

function T:test_the_files_are_the_executable_the_licence_and_the_completions()
  local names = {}
  for _, file in ipairs(self.files) do names[file.name] = file.mode end
  self:assert_equal(493, names["usr/bin/hecate"])
  self:assert_equal(420, names["usr/share/doc/hecate/copyright"])
  self:assert_equal(420, names["usr/share/bash-completion/completions/hecate"])
  self:assert_equal(420, names["usr/share/zsh/site-functions/_hecate"])
  self:assert_equal(420, names["usr/share/fish/vendor_completions.d/hecate.fish"])
  self:assert_equal(5, #self.files)
  local arch_files = linux_package.files("archlinux", { executable = "x", license = "l", completions = { bash = "b", zsh = "z", fish = "f" } })
  self:assert_equal("usr/share/licenses/hecate/LICENSE", arch_files[2].name)
  self:assert_error(function() linux_package.files("deb", { executable = "x", license = "l", completions = { bash = "b" } }) end, "no completion")
end

function T:test_the_ar_container_round_trips_and_pads_odd_members()
  local bytes = linux_package.ar({ { name = "debian-binary", data = "2.0\n" }, { name = "odd", data = "abc" }, { name = "last", data = "xy" } })
  self:assert_equal("!<arch>\n", bytes:sub(1, 8))
  self:assert_equal(0, #bytes % 2)
  local members = assert(linux_package.read_ar(bytes))
  self:assert_equal(3, #members)
  self:assert_equal("debian-binary", members[1].name)
  self:assert_equal("2.0\n", members[1].data)
  self:assert_equal("abc", members[2].data)
  self:assert_equal("xy", members[3].data)
  self:assert_equal("`\n", bytes:sub(8 + 59, 8 + 60))
end

function T:test_the_tar_holds_directories_and_owner_names()
  local bytes = archive.tar({ { name = "usr/", dir = true, data = "" }, { name = "usr/bin/hecate", data = "x", mode = 493 } }, { owner = "root" })
  local entries = assert(archive.read_tar(bytes))
  self:assert_equal(2, #entries)
  self:assert_true(entries[1].dir)
  self:assert_equal("usr/", entries[1].name)
  self:assert_equal(493, entries[1].mode)
  self:assert_equal("usr/bin/hecate", entries[2].name)
  self:assert_equal(493, entries[2].mode)
  self:assert_equal(0, entries[2].uid)
  self:assert_equal("root", entries[2].uname)
  self:assert_equal(1024, #archive.tar({}) )
  self:assert_equal(0, #archive.tar({}, { trailer = false }))
  self:assert_error(function() archive.tar({ { name = "usr", dir = true, data = "" } }) end, "bad directory")
end

function T:test_the_control_file_has_the_fields_dpkg_needs()
  local control = linux_package.deb_control(self.versions, 2049)
  for _, line in ipairs({ "Package: hecate", "Version: 0.4.2~rc1-3", "Architecture: amd64", "Installed-Size: 3", "Depends: libc6 (>= 2.28)",
    "Section: devel", "Priority: optional", "Homepage: https://github.com/hecate-framework/hecate" }) do
    self:assert_true(("\n" .. control):find("\n" .. line .. "\n", 1, true) ~= nil, line)
  end
  self:assert_true(control:find("Maintainer: ", 1, true) ~= nil)
  self:assert_true(control:find("\nDescription: Contract-first web API framework", 1, true) ~= nil)
  self:assert_true(control:find("\n .\n", 1, true) ~= nil, "an empty line of the description is a space and a dot")
  self:assert_equal("\n", control:sub(-1))
end

function T:test_the_md5sums_lists_every_file_without_a_leading_slash()
  local sums = linux_package.deb_md5sums(self.files)
  self:assert_true(sums:find(md5.hex(self.files[1].data) .. "  usr/bin/hecate\n", 1, true) ~= nil)
  self:assert_false(sums:find("  /", 1, true) ~= nil)
  local count = select(2, sums:gsub("\n", "\n"))
  self:assert_equal(5, count)
end

function T:test_the_deb_is_an_ar_of_three_members_and_is_deterministic()
  if not have("gzip --version") then return end
  local options = { scratch = self.dir }
  local deb = assert(linux_package.deb(self.files, self.versions, options))
  self:assert_true(deb == assert(linux_package.deb(self.files, self.versions, options)))
  local members = assert(linux_package.read_ar(deb))
  self:assert_equal("debian-binary control.tar.gz data.tar.gz", members[1].name .. " " .. members[2].name .. " " .. members[3].name)
  self:assert_equal("2.0\n", members[1].data)
  local path = self.dir .. "/hecate.deb"
  local f = assert(io.open(path, "wb"))
  f:write(deb)
  f:close()
  if have("dpkg-deb --version") then
    local info, ok = util.capture(("dpkg-deb --field %s Package Version Architecture Depends 2>&1"):format(util.quote(path)))
    self:assert_true(ok, info)
    self:assert_equal("Package: hecate\nVersion: 0.4.2~rc1-3\nArchitecture: amd64\nDepends: libc6 (>= 2.28)", info)
    local contents, listed = util.capture(("dpkg-deb --contents %s 2>&1"):format(util.quote(path)))
    self:assert_true(listed, contents)
    self:assert_true(contents:find("-rwxr-xr-x root/root", 1, true) ~= nil, contents)
    self:assert_true(contents:find("./usr/bin/hecate", 1, true) ~= nil, contents)
    self:assert_true(contents:find("./usr/share/doc/hecate/copyright", 1, true) ~= nil, contents)
    self:assert_true(contents:find("./usr/share/zsh/site-functions/_hecate", 1, true) ~= nil, contents)
    local extracted = self.dir .. "/extracted"
    util.mkdir(extracted)
    local _, ok_extract = util.capture(("dpkg-deb --extract %s %s 2>&1"):format(util.quote(path), util.quote(extracted)))
    self:assert_true(ok_extract)
    self:assert_equal(self.files[1].data, read(extracted .. "/usr/bin/hecate"))
    local md5_out, md5_ok = util.capture(("cd %s && dpkg-deb --control %s control 2>&1 && md5sum -c control/md5sums 2>&1")
      :format(util.quote(extracted), util.quote("../hecate.deb")))
    self:assert_true(md5_ok, md5_out)
  end
end

function T:test_the_arch_package_is_a_zstd_tar_with_pkginfo()
  local info = linux_package.archlinux_pkginfo(self.versions, 1234)
  for _, line in ipairs({ "pkgname = hecate", "pkgver = 0.4.2rc1-3", "arch = x86_64", "license = MIT", "size = 1234" }) do
    self:assert_true(info:find(line .. "\n", 1, true) ~= nil, line)
  end
  if not have("zstd --version") then return end
  local files = linux_package.files("archlinux", { executable = "bin\0ary", license = "MIT\n", completions = { bash = "b\n", zsh = "z\n", fish = "f\n" } })
  local package = assert(linux_package.archlinux(files, self.versions, { scratch = self.dir }))
  self:assert_equal("\40\181\47\253", package:sub(1, 4), "zstd magic")
  local path = self.dir .. "/p.pkg.tar.zst"
  local f = assert(io.open(path, "wb"))
  f:write(package)
  f:close()
  local tar, ok = util.capture(("zstd -d -q -c %s > %s && echo done"):format(util.quote(path), util.quote(self.dir .. "/p.tar")))
  self:assert_true(ok, tar)
  local entries = assert(archive.read_tar(assert(read(self.dir .. "/p.tar"))))
  self:assert_equal(".PKGINFO", entries[1].name)
  local names = {}
  for _, e in ipairs(entries) do names[e.name] = true end
  self:assert_true(names["usr/bin/hecate"] and names["usr/share/licenses/hecate/LICENSE"] and names["usr/"])
end

function T:test_the_apk_is_two_gzip_streams_and_the_datahash_names_the_second()
  local info = linux_package.apk_pkginfo(self.versions, 99, "abc123")
  for _, line in ipairs({ "pkgname = hecate", "pkgver = 0.4.2_rc1-r3", "arch = x86_64", "license = MIT", "datahash = abc123", "size = 99" }) do
    self:assert_true(info:find(line .. "\n", 1, true) ~= nil, line)
  end
  if not have("gzip --version") then return end
  local package = assert(linux_package.apk(self.files, self.versions, { scratch = self.dir }))
  self:assert_true(package == assert(linux_package.apk(self.files, self.versions, { scratch = self.dir })), "deterministic")
  -- the second gzip member starts at the second gzip magic after the first one
  local magic = "\31\139\8"
  local second = package:find(magic, 4, true)
  while second and package:sub(second, second + 3) ~= "\31\139\8\0" do second = package:find(magic, second + 1, true) end
  self:assert_not_nil(second, "two gzip streams")
  local control = self.dir .. "/control.tar.gz"
  local data = self.dir .. "/data.tar.gz"
  local f = assert(io.open(control, "wb"))
  f:write(package:sub(1, second - 1))
  f:close()
  f = assert(io.open(data, "wb"))
  f:write(package:sub(second))
  f:close()
  local control_tar = util.capture(("gzip -dc %s | wc -c"):format(util.quote(control)))
  self:assert_true(tonumber(control_tar) % 512 == 0 and tonumber(control_tar) == 1024, "one header and one block, no end-of-archive blocks")
  local pkginfo = util.capture(("gzip -dc %s | tar -xO .PKGINFO"):format(util.quote(control)))
  local datahash = pkginfo:match("datahash = (%x+)")
  self:assert_equal(require("lib.sha256").hex(assert(read(data))), datahash)
  local tar = util.capture(("gzip -dc %s > %s && echo ok"):format(util.quote(data), util.quote(self.dir .. "/data.tar")))
  self:assert_equal("ok", tar)
  local entries = assert(archive.read_tar(assert(read(self.dir .. "/data.tar"))))
  local names = {}
  for _, e in ipairs(entries) do names[e.name] = e end
  self:assert_equal(493, names["usr/bin/hecate"].mode)
  self:assert_equal("root", names["usr/bin/hecate"].uname)
end

function T:test_the_rpm_spec_lists_the_files_with_their_modes_and_the_licence()
  local files = linux_package.files("rpm", { executable = "x", license = "l", completions = { bash = "b", zsh = "z", fish = "f" } })
  local spec = linux_package.rpm_spec(self.versions, files)
  for _, line in ipairs({ "Name:           hecate", "Version:        0.4.2~rc1", "Release:        3", "License:        MIT",
    "%attr(0755,root,root) /usr/bin/hecate", "%attr(0644,root,root) %license /usr/share/licenses/hecate/LICENSE",
    "%attr(0644,root,root) /usr/share/zsh/site-functions/_hecate", "%dir %attr(0755,root,root) /usr/share/licenses/hecate",
    "cp -a %{hecate_staging}/. %{buildroot}/", "%global debug_package %{nil}" }) do
    self:assert_true(("\n" .. spec):find("\n" .. line .. "\n", 1, true) ~= nil, line)
  end
  self:assert_equal("\n", spec:sub(-1))
end

function T:test_an_rpm_is_built_by_rpmbuild_when_it_exists()
  if not have("rpmbuild --version") or not have("gzip --version") then return end
  local files = linux_package.files("rpm", { executable = ("binary\0bytes"):rep(500), license = "MIT License\n", completions = { bash = "b\n", zsh = "z\n", fish = "f\n" } })
  local rpm = assert(linux_package.rpm(files, self.versions, { scratch = self.dir }))
  self:assert_equal("\237\171\238\219", rpm:sub(1, 4), "rpm lead magic")
end

return T
