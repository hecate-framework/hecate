-- package-cli: makes the release archive of the `hecate` executable and its checksum, deterministically, and checks it.
-- Usage: package-cli [--version=<X.Y.Z[pre]-R>] [--exe=<path>] [--out=<dir>] [--os=<os>] [--arch=<arch>] [--no-smoke]
--      package-cli --check-tag=<X.Y.Z[pre]-R> [--prerelease]
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
local util = require("lib.util")
local sha256 = require("lib.sha256")
local archive = require("lib.archive")
local release_version = require("lib.release_version")
local windows = util.is_windows()

local M = {
  description = "package the hecate executable as a deterministic release archive with its sha256, and smoke-test it",
}

local OSES = { linux = true, darwin = true, windows = true }
local ARCHES = { x86_64 = true, aarch64 = true }

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

  local version = opts["check-tag"] or opts.version or (core_version .. "-1")
  local core, revision = M.parse_version(version)
  if not core then return { ok = false, problems = { "package-cli: " .. tostring(revision) } } end
  if core ~= core_version then
    return { ok = false, problems = { ("package-cli: the version %s does not match the VERSION file (%s): bump VERSION or fix the tag"):format(version, core_version) } }
  end
  if opts["check-tag"] then
    local flag = release_version.is_prerelease(core)
    return { ok = true, problems = {}, output = opts.prerelease and tostring(flag) or version, data = { version = version, core = core, revision = tonumber(revision), prerelease = flag } }
  end

  local os_name = opts.os or M.host_os()
  local arch = opts.arch or M.host_arch()
  if not (os_name and OSES[os_name]) then return { ok = false, problems = { "package-cli: unsupported operating system " .. tostring(os_name) } } end
  if not (arch and ARCHES[arch]) then return { ok = false, problems = { "package-cli: unsupported architecture " .. tostring(arch) } } end

  local exe_name = os_name == "windows" and "hecate.exe" or "hecate"
  local exe = (opts.exe or (root .. "/.hecate/build/cli/" .. exe_name)):gsub("\\", "/")
  local out_dir = (opts.out or (root .. "/.hecate/release/dist")):gsub("\\", "/")
  local binary = read(exe)
  if not binary or #binary == 0 then return { ok = false, problems = { "package-cli: cannot read the executable " .. exe .. " (run build-cli first)" } } end
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
      sha256 = digest, bytes = #bytes, entries = {}, smoke = "skipped" },
  }
  for _, entry in ipairs(entries) do report.data.entries[#report.data.entries + 1] = entry.name end
  if not opts["no-smoke"] then
    local ok, message = smoke(archive_path, name, core, os_name, root .. "/.hecate/tmp", ctx.run or util.capture)
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
