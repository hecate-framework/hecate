-- test [packages...]: runs tests/**/*_test.lua of the given packages (default: all)
-- under the bootstrap harness. The name `tools` selects tools/tests.
local util = require("lib.util")

local function files_in(dir) return util.walk(dir, "_test.lua") end

return {
  description = "run unit tests of packages (and `tools`) under the bootstrap harness",
  run = function(ctx)
    local problems, total = {}, 0
    local selected = #ctx.args > 0 and ctx.args or util.list_dir(ctx.root .. "/packages")
    local runner = ctx.root .. "/tools/harness/run_file.lua"
    for _, name in ipairs(selected) do
      local base = name == "tools" and (ctx.root .. "/tools") or (ctx.root .. "/packages/" .. name)
      local srcs = { base .. "/src", ctx.root .. "/tools" }
      for _, file in ipairs(files_in(base .. "/tests")) do
        total = total + 1
        local out, ok = util.capture(("%s %s %s %s %s 2>&1"):format(util.quote(util.interpreter()), util.quote(runner),
          util.quote(file), util.quote(srcs[1]), util.quote(srcs[2])))
        if not ok then problems[#problems + 1] = file:sub(#ctx.root + 2) .. "\n" .. out end
      end
    end
    return { ok = #problems == 0, problems = problems, count = total }
  end,
}
