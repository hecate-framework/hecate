-- check-package-structure: every packages/<name> has README.md, CLAUDE.md, a rockspec,
-- tests/ and an agent in .claude/agents/pkg-<name>.md.
local util = require("lib.util")

return {
  description = "every package has README, CLAUDE.md, rockspec, tests/ and its agent",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      local dir = pkgs .. "/" .. name
      if util.exists(dir .. "/.") and name ~= "README.md" then
        local required = {
          dir .. "/README.md",
          dir .. "/CLAUDE.md",
          dir .. "/hecate-" .. name .. "-scm-1.rockspec",
          dir .. "/tests",
          ctx.root .. "/.claude/agents/pkg-" .. name .. ".md",
        }
        for _, path in ipairs(required) do
          if not util.exists(path) then
            problems[#problems + 1] = ("packages/%s: missing %s"):format(name, path:sub(#ctx.root + 2))
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
