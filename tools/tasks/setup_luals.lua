-- setup-luals: installs the LuaLS release pinned in .github/workflows/ci.yml (version and sha256 per
-- platform, read from that file so there is a single pin) into `spikes/luals/` (git-ignored), after
-- checking the sha256 of the download. `typecheck` finds it there when `lua-language-server` is not on PATH.
-- Needs network access to github.com. Idempotent: does nothing when the pinned version is installed.
-- Only three platforms are pinned: Linux-x64, macOS-arm64 and Windows-x64 (the runners of ci.yml); any other host gets an
-- explicit error, and `typecheck` then needs a `lua-language-server` on PATH.
local util = require("lib.util")

--- A path with the separators of Windows, for the commands of the system (certutil, tar.exe).
---@param path string
---@return string
local function windows_path(path) return (path:gsub("/", "\\")) end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

--- Reads the pin of a platform from the CI workflow text.
---@param workflow string
---@param runner string `Linux-X64`, `macOS-ARM64` or `Windows-X64`
---@return string? version
---@return string? asset
---@return string? sha256
local function pin(workflow, runner)
  local version = workflow:match("LUALS_VERSION:%s*([%d%.]+)")
  local asset, sha = workflow:match(runner:gsub("%-", "%%-") .. "%)%s*asset=([%w%.%-]+);%s*sha=(%x+)")
  return version, asset, sha
end

--- The runner name of the current platform, in the vocabulary of GitHub Actions.
---@return string?
local function runner_name()
  if util.is_windows() then return "Windows-X64" end
  local uname = util.capture("uname -sm") or ""
  if uname:find("^Linux") and uname:find("x86_64") then return "Linux-X64" end
  if uname:find("^Darwin") and uname:find("arm64") then return "macOS-ARM64" end
  return nil
end

return {
  description = "install the pinned LuaLS into spikes/luals (sha256 checked), for typecheck",
  run = function(ctx)
    local runner = runner_name()
    if not runner then return { ok = false, problems = { "no pinned LuaLS for this platform (see ci.yml)" } } end
    local workflow = read(ctx.root .. "/.github/workflows/ci.yml")
    if not workflow then return { ok = false, problems = { "cannot read .github/workflows/ci.yml" } } end
    local version, asset, sha = pin(workflow, runner)
    if not (version and asset and sha) then
      return { ok = false, problems = { "no LuaLS pin for " .. runner .. " in ci.yml" } }
    end

    local dir = ctx.root .. "/spikes/luals"
    local stamp = dir .. "/.version"
    if (read(stamp) or ""):match("^%S+") == version then return { ok = true, problems = {} } end

    local file = ("lua-language-server-%s-%s"):format(version, asset)
    local archive = ctx.root .. "/spikes/" .. file
    util.mkdir(dir)
    local url = ("https://github.com/LuaLS/lua-language-server/releases/download/%s/%s"):format(version, file)
    local out, ok = util.capture(("curl -fsSL -o %s %s 2>&1"):format(util.quote(archive), '"' .. url .. '"'))
    if not ok then return { ok = false, problems = { "download failed (is github.com allowed?): " .. out } } end

    local data = read(archive)
    local digest
    if util.is_windows() then
      digest = util.capture(("certutil -hashfile %s SHA256"):format(util.quote(windows_path(archive)))):match("\n(%x[%x ]+)\r?\n")
      digest = digest and digest:gsub(" ", "")
    else
      digest = util.capture(("(sha256sum %s || shasum -a 256 %s) 2>/dev/null")
        :format(util.quote(archive), util.quote(archive))):match("^(%x+)")
    end
    if not data or digest ~= sha then
      os.remove(archive)
      return { ok = false, problems = { ("sha256 mismatch for %s: expected %s, got %s"):format(file, sha, tostring(digest)) } }
    end

    -- On Windows the system's own bsdtar: a `tar` found first on PATH may be another program (Git for Windows' GNU tar
    -- cannot read a zip and misreads `C:` as a remote host).
    local tar = "tar"
    if util.is_windows() then tar = util.quote((os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\tar.exe") end
    out, ok = util.capture(("%s -xf %s -C %s 2>&1"):format(tar, util.quote(util.is_windows() and windows_path(archive) or archive),
      util.quote(util.is_windows() and windows_path(dir) or dir)))
    os.remove(archive)
    if not ok then return { ok = false, problems = { "extraction failed: " .. out } } end
    local f = assert(io.open(stamp, "wb"))
    f:write(version, "\n")
    f:close()
    return { ok = true, problems = {} }
  end,
}
