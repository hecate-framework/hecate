-- gen-llms-txt: regenerates the "Packages" section of llms.txt (one line per package, from
-- the package READMEs) between <!-- gen-llms-txt:begin --> and <!-- gen-llms-txt:end -->.
-- The rest of llms.txt is curated by hand. Usage: gen-llms-txt [--check]
-- Not yet generated (they need the website, Phase 3): website/public/llms.txt and llms-full.txt.
local util = require("lib.util")
local catalogue = require("lib.catalogue")

local BEGIN, END = "<!-- gen-llms-txt:begin -->", "<!-- gen-llms-txt:end -->"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "regenerate the package list of llms.txt (--check to verify only)",
  run = function(ctx)
    local pkgs = {}
    for _, name in ipairs(util.list_dir(ctx.root .. "/packages")) do
      local text = read(("%s/packages/%s/README.md"):format(ctx.root, name))
      local meta = text and catalogue.parse_readme(text)
      if meta then pkgs[#pkgs + 1] = { name = name, meta = meta } end
    end
    catalogue.sort(pkgs)
    local lines = {}
    for _, p in ipairs(pkgs) do
      lines[#lines + 1] = ("- [%s](packages/%s/README.md): %s"):format(p.meta.rock, p.name, p.meta.summary)
    end
    local path = ctx.root .. "/llms.txt"
    local old = read(path) or ""
    local _, e = old:find(BEGIN, 1, true)
    local s2 = old:find(END, 1, true)
    if not (e and s2) then return { ok = false, problems = { "llms.txt: markers " .. BEGIN .. " / " .. END .. " not found" } } end
    local new = old:sub(1, e) .. "\n" .. table.concat(lines, "\n") .. "\n" .. old:sub(s2)
    local check = false
    for _, a in ipairs(ctx.args) do if a == "--check" then check = true end end
    if new ~= old then
      if check then return { ok = false, problems = { "llms.txt is out of date; run gen-llms-txt" } } end
      local f = assert(io.open(path, "wb"))
      f:write(new)
      f:close()
    end
    return { ok = true, problems = {} }
  end,
}
