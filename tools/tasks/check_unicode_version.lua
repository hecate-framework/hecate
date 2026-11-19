-- check-unicode-version: fails when a Unicode version newer than the pinned one is published (ADR 0032; the nightly
-- job `unicode-version`). The pinned version is the one of the URLs of packages/unicode-data/tests/external.lua; the
-- latest is announced by https://www.unicode.org/Public/UCD/latest/ReadMe.txt. It regenerates and publishes
-- nothing: updating is a human step (new pins, `fetch-fixtures`, `gen-unicode`, conformance, a new rock revision).
-- The download is hardened like `fetch-fixtures` (https only, redirects included, at most 1 MiB, a directory under
-- `.hecate/tmp` that is removed afterwards).
-- Usage: check-unicode-version [--readme <file>]   (`--readme` reads a local copy of the ReadMe instead of the network)
local ucd = require("lib.unicode_ucd")
local fixtures = require("lib.fixtures")
local util = require("lib.util")

local LATEST = "https://www.unicode.org/Public/UCD/latest/ReadMe.txt"
local MAX_BYTES = 1048576

return {
  description = "fail when a Unicode version newer than the pinned one is published (--readme <file> for an offline copy)",
  run = function(ctx)
    local readme_path
    local i = 1
    while i <= #ctx.args do
      if ctx.args[i] == "--readme" and ctx.args[i + 1] then
        readme_path = ctx.args[i + 1]
        i = i + 2
      else
        return { ok = false, problems = { "usage: check-unicode-version [--readme <file>]" } }
      end
    end
    local chunk = loadfile(ctx.root .. "/packages/unicode-data/tests/external.lua")
    if not chunk then return { ok = false, problems = { "packages/unicode-data/tests/external.lua is missing" } } end
    local pinned
    for _, entry in ipairs(chunk()) do pinned = pinned or ucd.version_of_url(entry.url or "") end
    if not pinned then return { ok = false, problems = { "no Unicode version in packages/unicode-data/tests/external.lua" } } end

    local text
    if readme_path then
      local f = io.open(readme_path, "rb")
      text = f and f:read("a")
      if f then f:close() end
      if not text then return { ok = false, problems = { "cannot read " .. readme_path } } end
    else
      -- The ReadMe is a few kilobytes: a larger answer is not the ReadMe (the limit also guards the memory).
      local directory = util.make_temp_dir(ctx.root .. "/.hecate/tmp", "unicode-version")
      if not directory then return { ok = false, problems = { "cannot create a directory under .hecate/tmp" } } end
      local path = directory .. "/ReadMe.txt"
      local out, ok = (ctx.download or fixtures.download)(LATEST, path, MAX_BYTES)
      local size = ok and fixtures.size(path)
      local f = size and size > 0 and size <= MAX_BYTES and io.open(path, "rb")
      text = f and f:read("a")
      if f then f:close() end
      util.remove_tree(directory)
      if not text then
        return { ok = false, problems = { "cannot download " .. LATEST .. ": " .. (ok and "empty or larger than " .. MAX_BYTES .. " bytes" or out) } }
      end
    end
    local latest = ucd.latest_version(text)
    if not latest then return { ok = false, problems = { "the ReadMe of " .. LATEST .. " names no Unicode version" } } end
    local data = { pinned = pinned, latest = latest }
    if ucd.compare_versions(latest, pinned) > 0 then
      return { ok = false, data = data, problems = { ("Unicode %s is published, the pinned version is %s: regenerate hecate-unicode-data " ..
        "(fetch-fixtures unicode-data, gen-unicode, conformance, a new rock revision; ADR 0032)"):format(latest, pinned) } }
    end
    return { ok = true, problems = {}, data = data, output = ("pinned %s, latest %s"):format(pinned, latest) }
  end,
}
