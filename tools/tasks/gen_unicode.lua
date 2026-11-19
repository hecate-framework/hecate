-- gen-unicode: generates the tables of `hecate.unicode_data` (packages/unicode-data/src/hecate/unicode_data/*.lua)
-- from the Unicode Character Database files pinned by packages/unicode-data/tests/external.lua and fetched by
-- `fetch-fixtures unicode-data` into .hecate/fixtures/unicode-data/ (ADR 0032). The inputs are verified against their
-- SHA-256 pins before use; the output is deterministic (sorted, no date) and carries the Unicode License v3 notice.
-- Usage: gen-unicode [--check]
-- `--check` writes nothing: it fails when a committed file differs from the generated one. Without the downloaded
-- inputs it fails and names the task that fetches them (the committed tables are still the ones that ship).
local util = require("lib.util")
local sha256 = require("lib.sha256")
local ucd = require("lib.unicode_ucd")

local OUT = "packages/unicode-data/src/hecate/unicode_data"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "generate hecate.unicode_data from the pinned UCD files (--check to verify only)",
  run = function(ctx)
    local check = false
    for _, a in ipairs(ctx.args) do
      if a == "--check" then check = true else return { ok = false, problems = { "usage: gen-unicode [--check]" } } end
    end
    local chunk = loadfile(ctx.root .. "/packages/unicode-data/tests/external.lua")
    if not chunk then return { ok = false, problems = { "packages/unicode-data/tests/external.lua is missing" } } end
    local problems, texts, names, version = {}, {}, {}, nil
    for _, entry in ipairs(chunk()) do
      local entry_version = ucd.version_of_url(entry.url or "")
      if not entry_version then
        problems[#problems + 1] = entry.name .. ": the url does not name a Unicode version (/Public/<version>/ucd/)"
      elseif version and entry_version ~= version then
        problems[#problems + 1] = ("%s: version %s, the other inputs are %s"):format(entry.name, entry_version, version)
      end
      version = version or entry_version
      local text = read(("%s/.hecate/fixtures/unicode-data/%s"):format(ctx.root, entry.name))
      if not text then
        problems[#problems + 1] = entry.name .. ": not downloaded (lua tools/run.lua fetch-fixtures unicode-data)"
      elseif sha256.hex(text) ~= entry.sha256 then
        problems[#problems + 1] = entry.name .. ": sha256 differs from the pin (lua tools/run.lua fetch-fixtures unicode-data)"
      else
        texts[entry.name] = text
        names[#names + 1] = entry.name
      end
    end
    if #problems > 0 then return { ok = false, problems = problems } end
    local ok, model = pcall(ucd.build, texts["UnicodeData.txt"], texts["DerivedNormalizationProps.txt"])
    if not ok then return { ok = false, problems = { tostring(model) } } end
    local files = ucd.render(model, { version = version, files = names })
    local dir = ctx.root .. "/" .. OUT
    local written, stale = {}, {}
    local list = {}
    for name in pairs(files) do list[#list + 1] = name end
    table.sort(list)
    for _, name in ipairs(list) do
      local path = dir .. "/" .. name
      if read(path) ~= files[name] then
        stale[#stale + 1] = name
        if not check then
          util.mkdir(dir)
          local f = assert(io.open(path, "wb"))
          f:write(files[name])
          f:close()
          written[#written + 1] = name
        end
      end
    end
    if check and #stale > 0 then
      return { ok = false, problems = { ("%s is out of date: %s (run gen-unicode)"):format(OUT, table.concat(stale, ", ")) },
        data = { version = version, stale = stale } }
    end
    return { ok = true, problems = {}, data = { version = version, written = written, count = #list } }
  end,
}
