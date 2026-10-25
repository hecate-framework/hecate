-- needs <package> [packages...]: tells whether a run that covers the given packages needs <package>, that is whether
-- one of them is <package> or depends on it (directly or not). Prints `true` or `false`. CI uses it to build the native
-- modules of `json` whenever a package that decodes or encodes JSON is affected, not only when `json` itself is.
local deps = require("lib.deps")
local affected = require("lib.affected")

return {
  description = "true when a listed package is, or depends on, <package> (decides which native modules CI builds)",
  run = function(ctx)
    local target = ctx.args[1]
    if not target then return { ok = false, problems = { "usage: needs <package> [packages...]" } } end
    local names = {}
    for i = 2, #ctx.args do names[#names + 1] = ctx.args[i] end
    local answer = affected.needs(names, target, deps.graph(ctx.root))
    return { ok = true, problems = {}, data = answer, output = tostring(answer) }
  end,
}
