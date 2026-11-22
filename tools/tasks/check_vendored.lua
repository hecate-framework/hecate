-- check-vendored [--online]: the integrity of the vendored third-party files that come from npm (ADR 0033: mermaid, and the
-- fonts of the theme and of the hello example, ADR 0012). Offline (the default) it verifies, for every VENDORED.md under
-- `packages/` and `examples/`, the SHA-256 table (the same code as `check-licenses`: `licenses.verify_text`; the vendored
-- copy must stay byte-identical to upstream) and the shape of the npm provenance it records (`tools/lib/vendored.lua`: the
-- `dist.integrity` and `dist.shasum` of the tarball, and the path of each vendored file inside it). With `--online` it adds
-- the registry step: each recorded tarball is downloaded again (hardened like `fetch-fixtures`: https only, redirects
-- included, at most 64 MiB, three tries), its SHA-512 is compared with the recorded `dist.integrity`, the recorded
-- file is read from the unpacked tarball and its SHA-256 compared with the table. It proves that the vendored bytes are
-- those the registry serves for that version today (a version npm unpublished or replaced is reported), and it changes
-- nothing. Scratch files live in a directory under `.hecate/tmp` that is removed afterwards. `--json` lists each directory.
-- The nightly job `vendored` runs `--online`; `ci` runs the offline check through `check-licenses` (packages only).
-- Tests inject `ctx.download`, `ctx.extract` and `ctx.pause`.
local util = require("lib.util")
local licenses = require("lib.licenses")
local sha256 = require("lib.sha256")
local sha512 = require("lib.sha512")
local vendored = require("lib.vendored")
local fixtures = require("lib.fixtures")
local retry = require("lib.retry")

local function relative(root, path) return (path:gsub("\\", "/"):sub(#root + 2)) end

-- Unpacks a gzip tar archive (`tar` is on Linux, macOS and Windows 10 and later, the system's own one on Windows) into
-- `directory`, which must exist afterwards: a failed `mkdir` is reported as such, not as a confusing `tar` error.
local function extract(archive, directory)
  util.mkdir(directory)
  if not util.is_dir(directory) then return ("cannot create the directory %s"):format(directory), false end
  local out, ok = util.capture(("%s -xzf %s -C %s 2>&1"):format(util.tar_command(), util.quote(archive), util.quote(directory)))
  return out, ok
end

local function verify_package(ctx, dir, package, files, digests, problems)
  local label = ("%s/VENDORED.md: npm package %s@%s"):format(dir, package.name, package.version)
  local scratch = util.make_temp_dir(ctx.root .. "/.hecate/tmp", "vendored")
  if not scratch then
    problems[#problems + 1] = label .. ": cannot create a directory under .hecate/tmp"
    return "failed"
  end
  local state = "failed"
  local archive = scratch .. "/package.tgz"
  local url = vendored.tarball_url(package.name, package.version)
  local out, ok = retry.run(function()
    return (ctx.download or fixtures.download)(url, archive, vendored.MAX_TARBALL)
  end, 3, 5, ctx.pause)
  local size = ok and fixtures.size(archive)
  if not ok then
    problems[#problems + 1] = ("%s: cannot download %s: %s"):format(label, url, out)
  elseif not size or size == 0 or size > vendored.MAX_TARBALL then
    problems[#problems + 1] = ("%s: the download of %s is empty or larger than %d bytes"):format(label, url, vendored.MAX_TARBALL)
  else
    local f = assert(io.open(archive, "rb"))
    local data = f:read("a")
    f:close()
    local integrity = sha512.integrity(data)
    if integrity ~= package.integrity then
      problems[#problems + 1] = ("%s: the tarball at %s has dist.integrity %s, recorded %s"):format(label, url, integrity,
        package.integrity)
    else
      local unpacked = scratch .. "/unpacked"
      local message, extracted = (ctx.extract or extract)(archive, unpacked)
      if not extracted then
        problems[#problems + 1] = ("%s: cannot unpack the tarball: %s"):format(label, message)
      else
        state = "verified"
        for _, row in ipairs(files) do
          if row.package == package.name then
            local file = io.open(("%s/package/%s"):format(unpacked, row.path), "rb")
            local content = file and file:read("a")
            if file then file:close() end
            local recorded
            for _, d in ipairs(digests) do if d.file == row.file then recorded = d.sha256 end end
            if not content then
              state = "failed"
              problems[#problems + 1] = ("%s: the tarball has no file %s (vendored as %s)"):format(label, row.path, row.file)
            elseif sha256.hex(content) ~= recorded then
              state = "failed"
              problems[#problems + 1] = ("%s: %s of the tarball does not have the SHA-256 recorded for %s"):format(label, row.path,
                row.file)
            end
          end
        end
      end
    end
  end
  util.remove_tree(scratch)
  return state
end

return {
  description = "verify the SHA-256 table and the npm provenance of every VENDORED.md (--online: against the registry)",
  run = function(ctx)
    local online = false
    for _, a in ipairs(ctx.args) do
      if a == "--online" then online = true else return { ok = false, problems = { "usage: check-vendored [--online]" } } end
    end
    local function read(path)
      local file = io.open(ctx.root .. "/" .. path, "rb")
      if not file then return nil end
      local data = file:read("a")
      file:close()
      return data
    end
    local dirs = {}
    for _, top in ipairs({ "packages", "examples" }) do
      for _, path in ipairs(util.walk(ctx.root .. "/" .. top, "VENDORED.md")) do
        if path:match("[^/\\]+$") == "VENDORED.md" then dirs[#dirs + 1] = (relative(ctx.root, path):gsub("/VENDORED%.md$", "")) end
      end
    end
    table.sort(dirs)
    local problems, report = {}, {}
    for _, dir in ipairs(dirs) do
      local text = read(dir .. "/VENDORED.md") or ""
      local digests = licenses.digests(text)
      for _, problem in ipairs(licenses.verify_text(dir, text, read, sha256.hex)) do problems[#problems + 1] = problem end
      local entry = { dir = dir, files = #digests, packages = {} }
      local packages, files = vendored.packages(text), vendored.files(text)
      for _, problem in ipairs(vendored.problems(dir, text, digests)) do problems[#problems + 1] = problem end
      for _, package in ipairs(packages) do
        local state = "recorded"
        if online then state = verify_package(ctx, dir, package, files, digests, problems) end
        entry.packages[#entry.packages + 1] = { name = package.name, version = package.version, state = state }
      end
      report[#report + 1] = entry
    end
    local count = 0
    for _, entry in ipairs(report) do count = count + #entry.packages end
    return {
      ok = #problems == 0, problems = problems, data = { online = online, directories = report },
      output = ("%d vendored directories, %d npm packages%s"):format(#report, count, online and " verified against the registry" or ""),
    }
  end,
}
