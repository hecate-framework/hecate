-- leaks [package...]: runs the reactor-heavy suites (default: reactor, net) with the harness leak check
-- (HECATE_TEST_LEAKS): a test that leaves libuv handles open fails.
local util = require("lib.util")
local leaks = require("lib.leaks")

return {
  description = "run reactor-heavy suites with libuv handle leak detection",
  run = function(ctx)
    local packages = #ctx.args > 0 and ctx.args or leaks.packages
    local problems = {}
    local args = {}
    for i, name in ipairs(packages) do args[i] = util.quote(name) end
    local out, ok = util.capture(("%s%s %s test %s 2>&1"):format(leaks.environment(util.is_windows()),
      util.quote(util.interpreter()), util.quote(ctx.root .. "/tools/run.lua"), table.concat(args, " ")))
    if not ok then problems[#problems + 1] = "leak check failed:\n" .. out end
    return { ok = #problems == 0, problems = problems }
  end,
}
