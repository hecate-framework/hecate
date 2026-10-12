-- affected: packages affected by a diff, following reverse dependencies.
-- Usage: affected [--base <ref>]   (default origin/main). Prints one package per line.
local util = require("lib.util")
local deps = require("lib.deps")
local affected = require("lib.affected")

return {
  description = "packages affected by a diff, with reverse dependencies (--base <ref>, default origin/main)",
  run = function(ctx)
    local base = "origin/main"
    for i, a in ipairs(ctx.args) do
      if a == "--base" then base = ctx.args[i + 1] or base end
    end
    local out, ok = util.capture(("git -C %s diff --name-only %s...HEAD"):format(util.quote(ctx.root), util.quote(base)))
    if not ok then return { ok = false, problems = { "cannot diff against " .. base } } end
    local files = {}
    for f in out:gmatch("[^\r\n]+") do files[#files + 1] = f end
    local list = affected.compute(files, deps.graph(ctx.root))
    return { ok = true, problems = {}, data = list, output = table.concat(list, "\n") }
  end,
}
