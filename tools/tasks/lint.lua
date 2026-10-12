-- lint [packages...]: lint rules on packages/*/src/**/*.lua (tools/lib/lint.lua).
local util = require("lib.util")
local lint = require("lib.lint")

return {
  description = "lint rules on package sources (compiles, declares globals)",
  run = function(ctx)
    local problems = {}
    local selected = #ctx.args > 0 and ctx.args or util.list_dir(ctx.root .. "/packages")
    for _, name in ipairs(selected) do
      local src = ctx.root .. "/packages/" .. name .. "/src"
      for _, file in ipairs(util.walk(src, ".lua")) do
        for _, p in ipairs(lint.check_file(file, file:sub(#ctx.root + 2))) do problems[#problems + 1] = p end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
