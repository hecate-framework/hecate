-- gen-catalogue: regenerates the table of packages/README.md from package READMEs.
-- Usage: gen-catalogue [--check]   (--check fails when the file is out of date)
local util = require("lib.util")
local catalogue = require("lib.catalogue")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "regenerate the package table of packages/README.md (--check to verify only)",
  run = function(ctx)
    local problems, pkgs = {}, {}
    for _, name in ipairs(util.list_dir(ctx.root .. "/packages")) do
      local text = read(("%s/packages/%s/README.md"):format(ctx.root, name))
      if text then
        local meta = catalogue.parse_readme(text)
        if meta then pkgs[#pkgs + 1] = { name = name, meta = meta }
        else problems[#problems + 1] = ("packages/%s/README.md: cannot read summary, Layer, Roadmap phase, Status and Rock"):format(name) end
      end
    end
    if #problems > 0 then return { ok = false, problems = problems } end
    local path = ctx.root .. "/packages/README.md"
    local old = read(path) or ""
    local new = catalogue.replace_table(old, catalogue.render(pkgs))
    local check = false
    for _, a in ipairs(ctx.args) do if a == "--check" then check = true end end
    if new ~= old then
      if check then return { ok = false, problems = { "packages/README.md is out of date; run gen-catalogue" } } end
      local f = assert(io.open(path, "wb"))
      f:write(new)
      f:close()
    end
    return { ok = true, problems = {} }
  end,
}
