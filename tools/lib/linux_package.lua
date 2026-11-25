-- Linux packages that a user installs from a file with the tool of the system (`dpkg`/`apt`, `rpm`/`dnf`, `pacman`, `apk`),
-- written in plain Lua from the built `hecate` executable, deterministically where the format allows (entries sorted, time
-- 1980-01-01, owner 0, the names `root`): `.deb`, `.rpm` (through `rpmbuild`), Arch `.pkg.tar.zst` and Alpine `.apk`.
-- Used by `package-cli --format=...`. Standard library plus `tools/lib` only; the compressors are external programs
-- (`gzip`, `zstd`) and `rpmbuild`, as `lib/archive.lua` uses `gzip`.
--
-- One metadata table (`M.METADATA`) feeds every format. The release version `X.Y.Z[alpha|beta|rc|pre]N-R`
-- (`lib/release_version.lua`) maps to each format's own syntax (`M.versions`):
--
--   release        0.4.2rc1-1             0.4.2-1
--   deb            0.4.2~rc1-1            0.4.2-1
--   rpm            Version 0.4.2~rc1      Version 0.4.2     (Release 1)
--   Arch           pkgver 0.4.2rc1        pkgver 0.4.2      (pkgrel 1; Arch has no tilde: rc1 sorts after the final)
--   Alpine         0.4.2_rc1-r1           0.4.2-r1
--
-- The tilde of Debian and RPM sorts before the empty string, so a pre-release is older than its final release; alpha,
-- beta, pre and rc are the suffixes of Alpine versions too.
local util = require("lib.util")
local archive = require("lib.archive")
local sha256 = require("lib.sha256")
local md5 = require("lib.md5")
local release_version = require("lib.release_version")

local M = {}

--- The formats `package-cli --format` knows besides the default archive.
M.FORMATS = { "deb", "rpm", "archlinux", "apk" }

--- The only architecture packaged for now (arm64 comes with its runners).
M.ARCH = "x86_64"

--- What every format says about the package (the single source).
M.METADATA = {
  name = "hecate",
  summary = "Contract-first web API framework for Lua 5.5: the hecate command-line tool",
  description = {
    "Hecate is a modular, contract-first web API framework for Lua 5.5 with its own asynchronous runtime, HTTP stack,",
    "schemas, OpenAPI generation, test framework and documentation generator.",
    "",
    "This package installs the self-contained hecate executable (Lua 5.5, LuaRocks and the native modules are built in),",
    "with the shell completions for bash, zsh and fish.",
  },
  homepage = "https://github.com/hecate-framework/hecate",
  maintainer = "Hecate maintainers <noreply@github.com>",
  license = "MIT",
  -- The oldest glibc the executable may need (`package-cli --max-glibc` defaults to it): the floor of the Debian and RPM dependency.
  glibc = "2.28",
}

---@class tools.PackageVersions
---@field release string   `X.Y.Z[pre]-R`
---@field numeric string   `X.Y.Z`
---@field prerelease string   `rc1`, or "" for a final version
---@field revision string
---@field deb string   `0.4.2~rc1-1`
---@field rpm_version string   `0.4.2~rc1`
---@field rpm_release string   `1`
---@field arch_version string   `0.4.2rc1` (pkgver)
---@field arch_release string   `1` (pkgrel)
---@field apk string   `0.4.2_rc1-r1`

--- Maps a release version to the version syntax of each format.
---@param release string   `X.Y.Z[alpha|beta|rc|pre]N-R`
---@return tools.PackageVersions? versions
---@return string? err
function M.versions(release)
  local base, revision = release_version.parse(release)
  if not base then return nil, ("'%s' is not a release version (X.Y.Z[pre]-R)"):format(tostring(release)) end
  local numeric, pre = release_version.split_base(base)
  ---@cast numeric string
  ---@cast pre string
  local token, number = pre:match("^(%a+)(%d+)$")
  local tilde = pre ~= "" and ("~" .. pre) or ""
  return {
    release = release, numeric = numeric, prerelease = pre, revision = revision,
    deb = numeric .. tilde .. "-" .. revision,
    rpm_version = numeric .. tilde, rpm_release = revision,
    arch_version = numeric .. pre, arch_release = revision,
    apk = numeric .. (token and ("_" .. token .. number) or "") .. "-r" .. revision,
  }
end

--- The name of the asset of `format` for a release.
---@param format string   deb, rpm, archlinux or apk
---@param versions tools.PackageVersions
---@return string
function M.asset_name(format, versions)
  if format == "deb" then return ("hecate_%s_amd64.deb"):format(versions.deb) end
  if format == "rpm" then return ("hecate-%s-%s.x86_64.rpm"):format(versions.rpm_version, versions.rpm_release) end
  if format == "archlinux" then return ("hecate-%s-%s-x86_64.pkg.tar.zst"):format(versions.arch_version, versions.arch_release) end
  if format == "apk" then return ("hecate-%s.x86_64.apk"):format(versions.apk) end
  error("linux_package: unknown format " .. tostring(format), 2)
end

-- ---- glibc floor ------------------------------------------------------------------------------------------------------

--- Compares two dotted numeric versions (`2.28`, `2.2.5`).
---@param a string
---@param b string
---@return integer   -1, 0 or 1
function M.compare_versions(a, b)
  local pa, pb = {}, {}
  for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

--- The highest `GLIBC_x.y[.z]` symbol version that a dynamic executable needs, read from the text of `objdump -T`
--- (`... (GLIBC_2.2.5) memcpy`) or `readelf --dyn-syms --wide` (`memcpy@GLIBC_2.14 (3)`). `GLIBC_PRIVATE` and the other
--- version families (`GLIBCXX_`) do not count. Nil when the text names no glibc version (a static or musl executable).
---@param text string
---@return string? highest
function M.highest_glibc(text)
  local highest
  for found in text:gmatch("GLIBC_(%d+[%.%d]*)") do
    local version = found:gsub("%.$", "")
    if not highest or M.compare_versions(version, highest) > 0 then highest = version end
  end
  return highest
end

-- ---- file layout -----------------------------------------------------------------------------------------------------

M.COMPLETIONS = {
  { shell = "bash", path = "usr/share/bash-completion/completions/hecate" },
  { shell = "zsh", path = "usr/share/zsh/site-functions/_hecate" },
  { shell = "fish", path = "usr/share/fish/vendor_completions.d/hecate.fish" },
}

--- Where the licence text goes: the Debian convention for a deb, the licence directory for the others.
---@param format string
---@return string
function M.license_path(format)
  if format == "deb" then return "usr/share/doc/hecate/copyright" end
  return "usr/share/licenses/hecate/LICENSE"
end

---@class tools.PackageInputs
---@field executable string   the bytes of the `hecate` executable
---@field license string   the text of the licence
---@field completions table<string, string>   `bash`, `zsh` and `fish`: the scripts printed by `hecate completion <shell>`

--- The files of a package, `/usr/bin/hecate` (0755), the licence and the three completions, as archive entries without a
--- leading slash.
---@param format string
---@param inputs tools.PackageInputs
---@return tools.ArchiveEntry[]
function M.files(format, inputs)
  local files = {
    { name = "usr/bin/hecate", data = inputs.executable, mode = 493 },
    { name = M.license_path(format), data = inputs.license, mode = 420 },
  }
  for _, c in ipairs(M.COMPLETIONS) do
    local script = inputs.completions[c.shell]
    if not script or script == "" then error("linux_package: no completion script for " .. c.shell, 2) end
    files[#files + 1] = { name = c.path, data = script, mode = 420 }
  end
  return files
end

--- The directories that hold `files`, parents first, as `usr/`, `usr/bin/`, ...
---@param files tools.ArchiveEntry[]
---@return string[]
local function directories(files)
  local seen, list = {}, {}
  for _, file in ipairs(files) do
    local path = ""
    for part in file.name:gmatch("([^/]+)/") do
      path = path .. part .. "/"
      if not seen[path] then
        seen[path] = true
        list[#list + 1] = path
      end
    end
  end
  table.sort(list)
  return list
end

--- The files and their directories as tar entries; `prefix` is "./" for a deb, "" otherwise.
local function tree_entries(files, prefix, with_root)
  local entries = {}
  if with_root then entries[#entries + 1] = { name = prefix, dir = true, mode = 493, data = "" } end
  for _, dir in ipairs(directories(files)) do entries[#entries + 1] = { name = prefix .. dir, dir = true, mode = 493, data = "" } end
  for _, file in ipairs(files) do entries[#entries + 1] = { name = prefix .. file.name, data = file.data, mode = file.mode } end
  return entries
end

local function installed_size(files)
  local total = 0
  for _, file in ipairs(files) do total = total + #file.data end
  return total
end

-- ---- compression -----------------------------------------------------------------------------------------------------

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

local function write(path, data)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(data)
  f:close()
  return true
end

--- Runs `command` as a filter over `bytes` through two files under a fresh directory of `scratch`.
---@param command string   reads standard input, writes standard output
---@param bytes string
---@param scratch string
---@return string? output
---@return string? err
local function filter(command, bytes, scratch)
  local dir = util.make_temp_dir(scratch, "filter")
  if not dir then return nil, "cannot create a scratch directory under " .. scratch end
  local ok, err = write(dir .. "/in", bytes)
  local output
  if ok then
    local out, success = util.capture(("%s < %s > %s"):format(command, util.quote(dir .. "/in"), util.quote(dir .. "/out")))
    if success then output = read(dir .. "/out") else err = command .. " failed: " .. out end
  end
  util.remove_tree(dir)
  if not output or output == "" then return nil, err or (command .. " wrote nothing") end
  return output
end

---@param bytes string
---@param scratch string
---@return string? gz
---@return string? err
function M.gzip(bytes, scratch) return filter("gzip -n -9 -c", bytes, scratch) end

---@param bytes string
---@param scratch string
---@return string? zst
---@return string? err
function M.zstd(bytes, scratch) return filter("zstd -19 -T1 -q -c", bytes, scratch) end

-- ---- deb -------------------------------------------------------------------------------------------------------------

--- The members of a `ar` archive (the container of a deb) in the given order: the header of a member is the name (16
--- bytes), time, owner, group, mode (octal) and size (decimal), then the two bytes "`\n"; the data is padded to an even
--- length with a newline.
---@param members { name: string, data: string, mode?: integer }[]
---@return string
function M.ar(members)
  local out = { "!<arch>\n" }
  for _, member in ipairs(members) do
    if #member.name > 15 then error("linux_package: ar member name too long: " .. member.name, 2) end
    out[#out + 1] = ("%-16s%-12d%-6d%-6d%-8o%-10d`\n"):format(member.name, archive.MTIME, 0, 0, (member.mode or 420) | 32768, #member.data)
    out[#out + 1] = member.data
    if #member.data % 2 == 1 then out[#out + 1] = "\n" end
  end
  return table.concat(out)
end

--- Reads an `ar` archive written by `M.ar`. Used by the tests.
---@param bytes string
---@return { name: string, data: string }[]? members
---@return string? err
function M.read_ar(bytes)
  if bytes:sub(1, 8) ~= "!<arch>\n" then return nil, "not an ar archive" end
  local members, position = {}, 9
  while position + 59 <= #bytes do
    local header = bytes:sub(position, position + 59)
    if header:sub(59, 60) ~= "`\n" then return nil, "bad member header" end
    local size = tonumber(header:sub(49, 58))
    members[#members + 1] = { name = header:sub(1, 16):match("^(%S+)"), data = bytes:sub(position + 60, position + 59 + size) }
    position = position + 60 + size + size % 2
  end
  return members
end

--- The wrapped paragraphs of the description in the `Description` syntax of a control file (continuation lines start with
--- a space, an empty line is a space and a dot).
local function control_description()
  local lines = {}
  for _, line in ipairs(M.METADATA.description) do lines[#lines + 1] = line == "" and " ." or (" " .. line) end
  return table.concat(lines, "\n")
end

--- The `control` file of the deb.
---@param versions tools.PackageVersions
---@param size integer   installed size in bytes
---@return string
function M.deb_control(versions, size)
  local m = M.METADATA
  return table.concat({
    "Package: " .. m.name,
    "Version: " .. versions.deb,
    "Architecture: amd64",
    "Maintainer: " .. m.maintainer,
    "Installed-Size: " .. ((size + 1023) // 1024),
    "Depends: libc6 (>= " .. m.glibc .. ")",
    "Section: devel",
    "Priority: optional",
    "Homepage: " .. m.homepage,
    "Description: " .. m.summary,
    control_description(),
  }, "\n") .. "\n"
end

--- The `md5sums` file: `<md5>  <path>` per file, without the leading slash.
---@param files tools.ArchiveEntry[]
---@return string
function M.deb_md5sums(files)
  local sorted = {}
  for i, file in ipairs(files) do sorted[i] = file end
  table.sort(sorted, function(a, b) return a.name < b.name end)
  local lines = {}
  for _, file in ipairs(sorted) do lines[#lines + 1] = md5.hex(file.data) .. "  " .. file.name end
  return table.concat(lines, "\n") .. "\n"
end

---@class tools.PackageOptions
---@field scratch string   a directory for the scratch files (`.hecate/tmp`)

--- The bytes of the `.deb`: an `ar` archive of `debian-binary`, `control.tar.gz` and `data.tar.gz`.
---@param files tools.ArchiveEntry[]
---@param versions tools.PackageVersions
---@param options tools.PackageOptions
---@return string? deb
---@return string? err
function M.deb(files, versions, options)
  local control_tar = archive.tar({
    { name = "./", dir = true, mode = 493, data = "" },
    { name = "./control", data = M.deb_control(versions, installed_size(files)), mode = 420 },
    { name = "./md5sums", data = M.deb_md5sums(files), mode = 420 },
  }, { owner = "root" })
  local data_tar = archive.tar(tree_entries(files, "./", true), { owner = "root" })
  local control_gz, err = M.gzip(control_tar, options.scratch)
  if not control_gz then return nil, err end
  local data_gz
  data_gz, err = M.gzip(data_tar, options.scratch)
  if not data_gz then return nil, err end
  return M.ar({
    { name = "debian-binary", data = "2.0\n" },
    { name = "control.tar.gz", data = control_gz },
    { name = "data.tar.gz", data = data_gz },
  })
end

-- ---- rpm -------------------------------------------------------------------------------------------------------------

--- The spec file for `rpmbuild`: the files are staged in `%{hecate_staging}` (defined on the command line) and copied
--- into the build root; no strip, no debug package, no changelog.
---@param versions tools.PackageVersions
---@param files tools.ArchiveEntry[]
---@return string
function M.rpm_spec(versions, files)
  local m = M.METADATA
  local lines = {
    "%global debug_package %{nil}",
    "%global _build_id_links none",
    "%global __os_install_post %{nil}",
    "",
    "Name:           " .. m.name,
    "Version:        " .. versions.rpm_version,
    "Release:        " .. versions.rpm_release,
    "Summary:        " .. m.summary,
    "License:        " .. m.license,
    "URL:            " .. m.homepage,
    "Packager:       " .. m.maintainer,
    "",
    "%description",
  }
  for _, line in ipairs(m.description) do lines[#lines + 1] = line end
  local license = M.license_path("rpm")
  for _, line in ipairs({
    "",
    "%install",
    "mkdir -p %{buildroot}",
    "cp -a %{hecate_staging}/. %{buildroot}/",
    "",
    "%files",
    "%dir %attr(0755,root,root) /" .. license:match("^(.*)/[^/]*$"),
  }) do lines[#lines + 1] = line end
  local sorted = {}
  for i, file in ipairs(files) do sorted[i] = file end
  table.sort(sorted, function(a, b) return a.name < b.name end)
  for _, file in ipairs(sorted) do
    lines[#lines + 1] = ("%%attr(%04o,root,root) %s/%s"):format(file.mode or 420, file.name == license and "%license " or "", file.name)
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Builds the `.rpm` with `rpmbuild` (an unsigned binary package) and returns its bytes.
---@param files tools.ArchiveEntry[]
---@param versions tools.PackageVersions
---@param options tools.PackageOptions
---@return string? rpm
---@return string? err
function M.rpm(files, versions, options)
  local top = util.make_temp_dir(options.scratch, "rpmbuild")
  if not top then return nil, "cannot create a scratch directory under " .. options.scratch end
  if not top:find("^/") then top = util.capture("pwd") .. "/" .. top end -- rpmbuild runs its scripts elsewhere
  local result, err
  local staging = top .. "/staging"
  for _, dir in ipairs(directories(files)) do util.mkdir(staging .. "/" .. dir) end
  local staged = true
  for _, file in ipairs(files) do
    local ok = write(staging .. "/" .. file.name, file.data)
    if not ok then staged = false break end
    util.capture(("chmod %o %s"):format(file.mode or 420, util.quote(staging .. "/" .. file.name)))
  end
  local spec = top .. "/hecate.spec"
  if staged and write(spec, M.rpm_spec(versions, files)) then
    local out, ok = util.capture(table.concat({
      "SOURCE_DATE_EPOCH=" .. archive.MTIME, "rpmbuild -bb --quiet --target " .. M.ARCH,
      "--define " .. util.quote("_topdir " .. top), "--define " .. util.quote("_rpmdir " .. top .. "/RPMS"),
      "--define " .. util.quote("hecate_staging " .. staging),
      "--define 'source_date_epoch_from_changelog 0' --define 'use_source_date_epoch_as_buildtime 1'",
      "--define 'clamp_mtime_to_source_date_epoch 1' --define '_buildhost hecate'",
      util.quote(spec), "2>&1",
    }, " "))
    if ok then
      result = read(("%s/RPMS/%s/%s"):format(top, M.ARCH, M.asset_name("rpm", versions)))
      if not result then err = "rpmbuild did not write " .. M.asset_name("rpm", versions) .. ":\n" .. out end
    else
      err = "rpmbuild failed:\n" .. out
    end
  else
    err = "cannot stage the files under " .. top
  end
  util.remove_tree(top)
  return result, err
end

-- ---- Arch Linux ------------------------------------------------------------------------------------------------------

--- The `.PKGINFO` file of the Arch package.
---@param versions tools.PackageVersions
---@param size integer   installed size in bytes
---@return string
function M.archlinux_pkginfo(versions, size)
  local m = M.METADATA
  return table.concat({
    "# Generated by tools/lib/linux_package.lua",
    "pkgname = " .. m.name,
    "pkgbase = " .. m.name,
    "pkgver = " .. versions.arch_version .. "-" .. versions.arch_release,
    "pkgdesc = " .. m.summary,
    "url = " .. m.homepage,
    "builddate = " .. archive.MTIME,
    "packager = " .. m.maintainer,
    "size = " .. size,
    "arch = x86_64",
    "license = " .. m.license,
    "xdata = pkgtype=pkg",
  }, "\n") .. "\n"
end

--- The bytes of the `.pkg.tar.zst`: a tar of `.PKGINFO` and the files, compressed with zstd. (There is no `.MTREE`: pacman
--- installs without it, and only `pacman -Qk` needs it.)
---@param files tools.ArchiveEntry[]
---@param versions tools.PackageVersions
---@param options tools.PackageOptions
---@return string? package
---@return string? err
function M.archlinux(files, versions, options)
  local entries = tree_entries(files, "", false)
  entries[#entries + 1] = { name = ".PKGINFO", data = M.archlinux_pkginfo(versions, installed_size(files)), mode = 420 }
  return M.zstd(archive.tar(entries, { owner = "root" }), options.scratch)
end

-- ---- Alpine ----------------------------------------------------------------------------------------------------------

--- The `.PKGINFO` file of the Alpine package.
---@param versions tools.PackageVersions
---@param size integer   installed size in bytes
---@param datahash string   sha256 (hexadecimal) of the gzip stream of the data
---@return string
function M.apk_pkginfo(versions, size, datahash)
  local m = M.METADATA
  return table.concat({
    "# Generated by tools/lib/linux_package.lua",
    "pkgname = " .. m.name,
    "pkgver = " .. versions.apk,
    "pkgdesc = " .. m.summary,
    "url = " .. m.homepage,
    "builddate = " .. archive.MTIME,
    "packager = " .. m.maintainer,
    "size = " .. size,
    "arch = x86_64",
    "origin = " .. m.name,
    "license = " .. m.license,
    "datahash = " .. datahash,
  }, "\n") .. "\n"
end

--- The bytes of the `.apk` (Alpine package format 2, unsigned): two gzip streams one after the other, the control tar
--- (`.PKGINFO`, without the end-of-archive blocks) and the data tar. `.PKGINFO` carries the sha256 of the data stream as
--- `datahash`. Install with `apk add --allow-untrusted`: there is no signature.
---@param files tools.ArchiveEntry[]
---@param versions tools.PackageVersions
---@param options tools.PackageOptions
---@return string? package
---@return string? err
function M.apk(files, versions, options)
  local data_gz, err = M.gzip(archive.tar(tree_entries(files, "", false), { owner = "root" }), options.scratch)
  if not data_gz then return nil, err end
  local info = M.apk_pkginfo(versions, installed_size(files), sha256.hex(data_gz))
  local control_gz
  control_gz, err = M.gzip(archive.tar({ { name = ".PKGINFO", data = info, mode = 420 } }, { owner = "root", trailer = false }), options.scratch)
  if not control_gz then return nil, err end
  return control_gz .. data_gz
end

--- Writes the package of `format`.
---@param format string
---@param files tools.ArchiveEntry[]
---@param versions tools.PackageVersions
---@param options tools.PackageOptions
---@return string? bytes
---@return string? err
function M.build(format, files, versions, options)
  local writer = ({ deb = M.deb, rpm = M.rpm, archlinux = M.archlinux, apk = M.apk })[format]
  if not writer then return nil, "unknown package format " .. tostring(format) end
  return writer(files, versions, options)
end

return M
