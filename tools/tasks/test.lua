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
      -- Every package source tree is on the path so a package can require its declared
      -- dependencies (for example hecate.core from hecate.reactor); native rocks such as luv
      -- are found through the caller's LUA_CPATH.
      local srcs = { base .. "/src", ctx.root .. "/tools" }
      for _, other in ipairs(util.list_dir(ctx.root .. "/packages")) do
        if other ~= name then srcs[#srcs + 1] = ctx.root .. "/packages/" .. other .. "/src" end
      end
      for _, file in ipairs(files_in(base .. "/tests")) do
        total = total + 1
        -- CI sets CI=true: name the file before running it, so a cancelled run shows where it stopped.
        if os.getenv("CI") then io.stderr:write("# test ", file:sub(#ctx.root + 2), "\n") end
        local quoted = {}
        for i, dir in ipairs(srcs) do quoted[i] = util.quote(dir) end
        -- `sanitize` on macOS: DYLD_* variables do not survive the system shell, so the variables of the
        -- sanitizer run are set on the command of each file.
        local inline = os.getenv("HECATE_SANITIZE_ENV")
        local out, ok = util.capture(("%s%s %s %s %s 2>&1"):format(inline and (inline .. " ") or "", util.quote(util.interpreter()), util.quote(runner),
          util.quote(file), table.concat(quoted, " ")))
        if not ok then problems[#problems + 1] = file:sub(#ctx.root + 2) .. "\n" .. out end
      end
    end
    return { ok = #problems == 0, problems = problems, count = total }
  end,
}
