-- package-cli: makes the release archive of the `hecate` executable, or a Linux package, and its checksum,
-- deterministically, and checks it.
-- Usage: package-cli [--version=<X.Y.Z[pre]-R>] [--exe=<path>] [--out=<dir>] [--os=<os>] [--arch=<arch>] [--no-smoke]
--                    [--format=archive|deb|rpm|archlinux|apk] [--max-glibc=<x.y>|none]
--      package-cli --check-tag=<X.Y.Z[pre]-R> [--prerelease]
--      package-cli --list-assets=<X.Y.Z[pre]-R>
--   The version is the LuaRocks form `<VERSION>-<revision>` (no `v` prefix): `X.Y.Z` must equal the root `VERSION` file, the
--   revision is a number (default: `<VERSION>-1`). `X.Y.Z` may be followed directly by a pre-release, `alpha`, `beta`, `rc` or
--   `pre` and a number (`0.4.2rc1-1`, from a VERSION file that holds `0.4.2rc1`): the grammar is `lib/release_version.lua`.
--   With `--prerelease`, `--check-tag` prints `true` or `false` (whether the version has a pre-release part) instead of the
--   version, for the `--prerelease` flag of `gh release create`. `--check-tag` only validates a tag name (the release workflow's first
--   job, so that a wrong tag fails before the build) and prints the version.
--   Output (default `.hecate/release/dist`), with <os> in linux|darwin|windows and <arch> in x86_64|aarch64 (detected from
--   `uname`, or from PROCESSOR_ARCHITECTURE on Windows; `--os` and `--arch` override):
--     hecate-<version>-<os>-<arch>.tar.gz   (`.zip` on Windows): `hecate` at the root of the archive (`hecate.exe` and
--                                           `lua55.dll`, taken from the directory of the executable, on Windows)
--     hecate-<version>-<os>-<arch>.<ext>.sha256   `<hex>  <archive name>` (sha256sum format)
--   The archive is deterministic: entries sorted, time 1980-01-01, owner 0, modes 0755 (executable) and 0644; the tar is
--   compressed by `gzip -n -9` (the bytes then depend on the gzip implementation), the zip holds stored entries (no
--   compression: Windows has no deterministic compressor to call). The smoke check extracts the archive into a scratch
--   directory and runs `hecate version`, which must print `Hecate X.Y.Z`. Standard library only (plus `gzip` for the tar).
--   `--format` other than `archive` (the default) writes a Linux package of the executable instead (`lib/linux_package.lua`):
--   `deb`, `rpm` (needs `rpmbuild`), `archlinux` (needs `zstd`) or `apk`; x86_64 only for now. The package also holds the
--   licence and the completions that the executable itself prints (`hecate completion bash|zsh|fish`, so it must run on
--   this host). Names: `hecate_<deb version>_amd64.deb`, `hecate-<version>-<release>.x86_64.rpm`,
--   `hecate-<pkgver>-<pkgrel>-x86_64.pkg.tar.zst`, `hecate-<alpine version>.x86_64.apk`, each with a `.sha256`. These
--   packages are installed in a real distribution by the release workflow, not by this task (the smoke result is "skipped").
--   The glibc guard: a Linux executable that links against glibc must not need a symbol version above `--max-glibc` (default
--   2.28, the floor of the release: it is built on AlmaLinux 8); `--max-glibc=none` skips the check, which is also skipped
--   for an executable that is not ELF or names no glibc version (static, musl). It reads `objdump -T`, else `readelf`.
--   `--list-assets` prints the name of every file of a release (archives, packages and their `.sha256`), for the
--   release workflow to check what it attaches.
local util = require("lib.util")
local sha256 = require("lib.sha256")
local archive = require("lib.archive")
local release_version = require("lib.release_version")
local linux_package = require("lib.linux_package")
local windows = util.is_windows()

local M = {
  description = "package the hecate executable as a deterministic release archive with its sha256, and smoke-test it",
}

local OSES = { linux = true, darwin = true, windows = true }
local ARCHES = { x86_64 = true, aarch64 = true }

--- The platforms of the first release (owner decision of 2026-11-25), as `release.yml` builds them: the archive of each,
--- and the Linux packages of the first. macOS is the architecture of the `macos-latest` runner.
M.RELEASE_TARGETS = { { "linux", "x86_64" }, { "darwin", "aarch64" }, { "windows", "x86_64" } }

--- The default `--max-glibc`: the glibc of AlmaLinux 8, older than every supported Debian, Ubuntu and RHEL release.
M.DEFAULT_MAX_GLIBC = "2.28"

--- Splits `X.Y.Z[pre]-R` (`tools/lib/release_version.lua`); nil and a message when the string is not that form.
---@param version string
---@return string? core   `X.Y.Z` or `X.Y.Z` and a pre-release (`0.4.2rc1`)
---@return string? revision
function M.parse_version(version)
  local core, revision = release_version.parse(version)
  if not core then return nil, ("'%s' is not a release version (expected X.Y.Z[pre]-R, no 'v' prefix, pre being alpha, beta, rc or pre and a number, e.g. 0.1.0-1 or 0.4.2rc1-1)"):format(tostring(version)) end
  return core, revision
end

--- The operating system name of the assets: linux, darwin or windows.
---@param uname_s? string   the output of `uname -s` (default: asked of the system)
---@param on_windows? boolean
---@return string? os
function M.host_os(uname_s, on_windows)
  if on_windows == nil then on_windows = windows end
  if on_windows then return "windows" end
  uname_s = uname_s or util.capture("uname -s")
  local name = uname_s:lower()
  if name == "linux" then return "linux" end
  if name == "darwin" then return "darwin" end
  return nil
end

--- The architecture name of the assets: x86_64 or aarch64.
---@param machine? string   `uname -m`, or PROCESSOR_ARCHITECTURE on Windows (default: asked of the system)
---@return string? arch
function M.host_arch(machine)
  machine = (machine or (windows and os.getenv("PROCESSOR_ARCHITECTURE") or util.capture("uname -m")) or ""):lower()
  if machine == "x86_64" or machine == "amd64" or machine == "x64" then return "x86_64" end
  if machine == "aarch64" or machine == "arm64" then return "aarch64" end
  return nil
end

--- The archive name: `hecate-<version>-<os>-<arch>.tar.gz`, `.zip` on Windows.
---@param version string
---@param os_name string
---@param arch string
---@return string
function M.archive_name(version, os_name, arch)
  return ("hecate-%s-%s-%s.%s"):format(version, os_name, arch, os_name == "windows" and "zip" or "tar.gz")
end

--- The names of every file that a release attaches: archive and packages, each with its `.sha256`.
---@param version string   `X.Y.Z[pre]-R`
---@return string[]? names
---@return string? err
function M.release_assets(version)
  local versions, err = linux_package.versions(version)
  if not versions then return nil, err end
  local names = {}
  for _, target in ipairs(M.RELEASE_TARGETS) do names[#names + 1] = M.archive_name(version, target[1], target[2]) end
  for _, format in ipairs(linux_package.FORMATS) do names[#names + 1] = linux_package.asset_name(format, versions) end
  local count = #names
  for i = 1, count do names[count + i] = names[i] .. ".sha256" end
  table.sort(names)
  return names
end

--- Checks the glibc symbol versions that a Linux executable needs against `max`.
---@param exe string   path of the executable
---@param binary string   its bytes
---@param max string   `2.28`, or `none`
---@param run fun(cmd: string): string, boolean
---@return boolean ok
---@return string message   the highest glibc version found, or why the check was skipped, or what is wrong
---@return string? highest
function M.check_glibc(exe, binary, max, run)
  if max == "none" then return true, "skipped (--max-glibc=none)" end
  if binary:sub(1, 4) ~= "\127ELF" then return true, "skipped (not an ELF executable)" end
  local text, ok = run(("objdump -T %s 2>&1"):format(util.quote(exe)))
  if not ok and not text:find("not a dynamic object", 1, true) then
    text, ok = run(("readelf --dyn-syms --wide %s 2>&1"):format(util.quote(exe)))
    if not ok then return false, "cannot read the symbol versions of " .. exe .. " (objdump and readelf failed: " .. text .. ")" end
  end
  local highest = linux_package.highest_glibc(text)
  if not highest then return true, "skipped (no glibc symbol version: a static or musl executable)" end
  if linux_package.compare_versions(highest, max) > 0 then
    return false, ("%s needs glibc %s, above the floor %s (build it in a container with an older glibc, see docs/architecture/cli-and-packaging.md, \"Releases\")"):format(exe, highest, max), highest
  end
  return true, "glibc " .. highest .. " (at most " .. max .. ")", highest
end

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

--- The version of the root `VERSION` file.
local function project_version(root)
  local text = read(root .. "/VERSION")
  return text and text:match("^%s*(%S+)")
end

--- Extracts the archive into a fresh directory under `scratch`, runs `hecate version` and checks the version.
---@return boolean ok
---@return string message
local function smoke(archive_path, name, core, os_name, scratch, run)
  local dir = util.make_temp_dir(scratch, "smoke")
  if not dir then return false, "cannot create a scratch directory under " .. scratch end
  local flags = os_name == "windows" and "-xf" or "-xzf"
  local out, ok = run(("%s %s %s -C %s 2>&1"):format(util.tar_command(), flags, util.quote(archive_path), util.quote(dir)))
  local executable = dir .. "/hecate" .. (os_name == "windows" and ".exe" or "")
  local message
  if not ok then
    message = "cannot extract " .. name .. ": " .. out
  elseif not util.exists(executable) then
    message = name .. " does not hold " .. executable:match("[^/]+$") .. " at its root"
  else
    out, ok = run(("%s version 2>&1"):format(util.quote(executable)))
    local wanted = "Hecate " .. core .. " ("
    if not ok then message = "`hecate version` failed: " .. out
    elseif not out:find(wanted, 1, true) then message = ("`hecate version` printed %q, expected it to start with %q"):format(out, wanted:sub(1, -3))
    else
      util.remove_tree(dir)
      return true, out
    end
  end
  util.remove_tree(dir)
  return false, message
end

--- Writes the Linux package `spec.format` of the executable and its checksum.
---@param ctx table
---@param spec { version: string, format: string, exe: string, binary: string, out: string, run: fun(cmd: string): string, boolean, glibc: table? }
---@return table report
function M.package(ctx, spec)
  local license = read(ctx.root .. "/LICENSE")
  if not license then return { ok = false, problems = { "package-cli: cannot read " .. ctx.root .. "/LICENSE" } } end
  local completions = {}
  for _, c in ipairs(linux_package.COMPLETIONS) do
    local out, ok = spec.run(("%s completion %s"):format(util.quote(spec.exe), c.shell))
    if not ok or out == "" then
      return { ok = false, problems = { ("package-cli: `%s completion %s` failed (the executable must run on this host): %s"):format(spec.exe, c.shell, out) } }
    end
    completions[c.shell] = out .. "\n"
  end
  local versions, err = linux_package.versions(spec.version)
  if not versions then return { ok = false, problems = { "package-cli: " .. tostring(err) } } end
  local files = linux_package.files(spec.format, { executable = spec.binary, license = license, completions = completions })
  local scratch = ctx.root .. "/.hecate/tmp"
  util.mkdir(scratch)
  if not util.mkdir(spec.out) and not util.is_dir(spec.out) then return { ok = false, problems = { "package-cli: cannot create " .. spec.out } } end
  local bytes, build_err = linux_package.build(spec.format, files, versions, { scratch = scratch })
  if not bytes then return { ok = false, problems = { "package-cli: " .. tostring(build_err) } } end
  local name = linux_package.asset_name(spec.format, versions)
  local path = spec.out .. "/" .. name
  local ok, werr = write(path, bytes)
  if not ok then return { ok = false, problems = { "package-cli: cannot write " .. path .. ": " .. tostring(werr) } } end
  local digest = sha256.hex(bytes)
  ok, werr = write(path .. ".sha256", ("%s  %s\n"):format(digest, name))
  if not ok then return { ok = false, problems = { "package-cli: cannot write the checksum: " .. tostring(werr) } } end
  local entries = {}
  for _, file in ipairs(files) do entries[#entries + 1] = "/" .. file.name end
  table.sort(entries)
  return {
    ok = true, problems = {}, output = ("%s\n%s  %s"):format(path, digest, name),
    data = { version = spec.version, os = "linux", arch = linux_package.ARCH, format = spec.format, archive = path, checksum = path .. ".sha256",
      sha256 = digest, bytes = #bytes, entries = entries, smoke = "skipped", glibc = spec.glibc },
  }
end

---@param ctx table   { root, args, run? } (`run` runs a shell command and returns its output and success: tests inject it)
function M.run(ctx)
  local opts = {}
  for _, a in ipairs(ctx.args) do
    local key, value = a:match("^%-%-([%w-]+)=(.*)$")
    if key then opts[key] = value elseif a == "--no-smoke" then opts["no-smoke"] = true
    elseif a == "--prerelease" then opts.prerelease = true
    else return { ok = false, problems = { "package-cli: unknown argument " .. a } } end
  end
  local root = ctx.root
  local core_version = project_version(root)
  if not core_version then return { ok = false, problems = { "package-cli: cannot read " .. root .. "/VERSION" } } end

  local version = opts["check-tag"] or opts["list-assets"] or opts.version or (core_version .. "-1")
  local core, revision = M.parse_version(version)
  if not core then return { ok = false, problems = { "package-cli: " .. tostring(revision) } } end
  if core ~= core_version then
    return { ok = false, problems = { ("package-cli: the version %s does not match the VERSION file (%s): bump VERSION or fix the tag"):format(version, core_version) } }
  end
  if opts["list-assets"] then
    local names, err = M.release_assets(version)
    if not names then return { ok = false, problems = { "package-cli: " .. tostring(err) } } end
    return { ok = true, problems = {}, output = table.concat(names, "\n"), data = { version = version, assets = names } }
  end
  if opts["check-tag"] then
    local flag = release_version.is_prerelease(core)
    return { ok = true, problems = {}, output = opts.prerelease and tostring(flag) or version, data = { version = version, core = core, revision = tonumber(revision), prerelease = flag } }
  end

  local os_name = opts.os or M.host_os()
  local arch = opts.arch or M.host_arch()
  if not (os_name and OSES[os_name]) then return { ok = false, problems = { "package-cli: unsupported operating system " .. tostring(os_name) } } end
  if not (arch and ARCHES[arch]) then return { ok = false, problems = { "package-cli: unsupported architecture " .. tostring(arch) } } end

  local format = opts.format or "archive"
  if format ~= "archive" then
    local known = false
    for _, f in ipairs(linux_package.FORMATS) do known = known or f == format end
    if not known then return { ok = false, problems = { ("package-cli: unknown --format %s (archive, %s)"):format(format, table.concat(linux_package.FORMATS, ", ")) } } end
    if os_name ~= "linux" then return { ok = false, problems = { "package-cli: the " .. format .. " package is for Linux (--os=" .. os_name .. ")" } } end
    if arch ~= linux_package.ARCH then return { ok = false, problems = { "package-cli: the Linux packages are built for " .. linux_package.ARCH .. " only for now (arm64 comes with its runners), not " .. arch } } end
  end

  local exe_name = os_name == "windows" and "hecate.exe" or "hecate"
  local exe = (opts.exe or (root .. "/.hecate/build/cli/" .. exe_name)):gsub("\\", "/")
  local out_dir = (opts.out or (root .. "/.hecate/release/dist")):gsub("\\", "/")
  local binary = read(exe)
  if not binary or #binary == 0 then return { ok = false, problems = { "package-cli: cannot read the executable " .. exe .. " (run build-cli first)" } } end
  local run = ctx.run or util.capture
  local glibc
  if os_name == "linux" then
    local ok, message, highest = M.check_glibc(exe, binary, opts["max-glibc"] or M.DEFAULT_MAX_GLIBC, run)
    if not ok then return { ok = false, problems = { "package-cli: " .. message } } end
    glibc = { highest = highest, max = opts["max-glibc"] or M.DEFAULT_MAX_GLIBC, result = message }
  end
  if format ~= "archive" then return M.package(ctx, { version = version, format = format, exe = exe, binary = binary, out = out_dir, run = run, glibc = glibc }) end
  local entries = { { name = exe_name, data = binary, mode = 493 } }
  if os_name == "windows" then
    local dll_path = (exe:match("^(.*)/[^/]*$") or ".") .. "/lua55.dll"
    local dll = read(dll_path)
    if not dll then return { ok = false, problems = { "package-cli: lua55.dll must sit beside the executable: " .. dll_path } } end
    entries[#entries + 1] = { name = "lua55.dll", data = dll, mode = 420 }
  end

  if not util.mkdir(out_dir) and not util.is_dir(out_dir) then return { ok = false, problems = { "package-cli: cannot create " .. out_dir } } end
  local name = M.archive_name(version, os_name, arch)
  local archive_path = out_dir .. "/" .. name
  if os_name == "windows" then
    local ok, err = write(archive_path, archive.zip(entries))
    if not ok then return { ok = false, problems = { "package-cli: cannot write " .. archive_path .. ": " .. tostring(err) } } end
  else
    local tar_path = archive_path .. ".tar.tmp"
    local wrote, werr = write(tar_path, archive.tar(entries))
    if not wrote then return { ok = false, problems = { "package-cli: cannot write " .. tar_path .. ": " .. tostring(werr) } } end
    local ok, err = archive.gzip(tar_path, archive_path)
    os.remove(tar_path)
    if not ok then return { ok = false, problems = { "package-cli: " .. tostring(err) } } end
  end

  local bytes = read(archive_path)
  if not bytes or #bytes == 0 then return { ok = false, problems = { "package-cli: the archive " .. archive_path .. " is empty" } } end
  local digest = sha256.hex(bytes)
  local wrote, werr = write(archive_path .. ".sha256", ("%s  %s\n"):format(digest, name))
  if not wrote then return { ok = false, problems = { "package-cli: cannot write the checksum: " .. tostring(werr) } } end

  local report = {
    ok = true, problems = {},
    data = { version = version, os = os_name, arch = arch, archive = archive_path, checksum = archive_path .. ".sha256",
      sha256 = digest, bytes = #bytes, entries = {}, smoke = "skipped", glibc = glibc },
  }
  for _, entry in ipairs(entries) do report.data.entries[#report.data.entries + 1] = entry.name end
  if not opts["no-smoke"] then
    local ok, message = smoke(archive_path, name, core, os_name, root .. "/.hecate/tmp", run)
    report.data.smoke = ok and "passed" or "failed"
    if not ok then
      report.ok = false
      report.problems[#report.problems + 1] = "package-cli: smoke test: " .. message
    end
  end
  report.output = ("%s\n%s  %s"):format(archive_path, digest, name)
  return report
end

return M
