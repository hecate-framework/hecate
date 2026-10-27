-- gen-reference: Markdown reference pages from the LuaLS JSON export, written to
-- website/en/reference/<package>/ (documentation.md, "Generated reference"). The pages are not
-- committed (git-ignored): the website workflow runs this task before the site build.
-- Usage: gen-reference [--packages core,reactor,net,json,log] [--require]
-- Without `lua-language-server` on the path the task is skipped with a message; `--require`
-- turns the skip into a failure (CI). The work is done by packages/doc/bin/reference.lua.
local util = require("lib.util")

return {
  description = "generate the code reference pages from the LuaLS export (needs lua-language-server; --require fails without it)",
  run = function(ctx)
    local packages, required
    local i = 1
    while i <= #ctx.args do
      local a = ctx.args[i]
      if a == "--packages" and ctx.args[i + 1] then
        packages = ctx.args[i + 1]
        i = i + 1
      elseif a == "--require" then
        required = true
      else
        return { ok = false, problems = { "usage: gen-reference [--packages a,b,c] [--require]" } }
      end
      i = i + 1
    end
    local probe = util.is_windows() and "where lua-language-server 2>nul" or "command -v lua-language-server"
    local _, found = util.capture(probe)
    if not found then
      local message = "gen-reference skipped: lua-language-server is not on the path (see tools/bootstrap); "
        .. "the reference pages were not generated"
      if required then return { ok = false, problems = { message } } end
      return { ok = true, problems = {}, output = message }
    end
    local command = ("%s %s --root %s%s 2>&1"):format(util.quote(util.interpreter()),
      util.quote(ctx.root .. "/packages/doc/bin/reference.lua"), util.quote(ctx.root),
      packages and (" --packages " .. util.quote(packages)) or "")
    local out, ok = util.capture(command)
    if not ok then return { ok = false, problems = { out } } end
    return { ok = true, problems = {}, output = out }
  end,
}
