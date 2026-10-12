-- check-changelog: a change touching packages/ must also change CHANGELOG.md.
-- Usage: check-changelog [--base <ref>]   (default origin/main)
local util = require("lib.util")

return {
  description = "changes under packages/ add a CHANGELOG.md entry (--base <ref>, default origin/main)",
  run = function(ctx)
    local base = "origin/main"
    for i, a in ipairs(ctx.args) do
      if a == "--base" then base = ctx.args[i + 1] or base end
    end
    local out, ok = util.capture(("git -C %s diff --name-only %s...HEAD"):format(util.quote(ctx.root), util.quote(base)))
    if not ok then return { ok = false, problems = { "cannot diff against " .. base } } end
    local packages, changelog = false, false
    for file in out:gmatch("[^\r\n]+") do
      if file:match("^packages/") and not file:match("/README%.md$") then packages = true end
      if file == "CHANGELOG.md" then changelog = true end
    end
    if packages and not changelog then
      return { ok = false, problems = { "packages/ changed but CHANGELOG.md has no [Unreleased] entry" } }
    end
    return { ok = true, problems = {} }
  end,
}
