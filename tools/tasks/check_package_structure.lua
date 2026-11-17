-- check-package-structure: every packages/<name> has README.md, CLAUDE.md, a rockspec,
-- tests/ and an agent in .claude/agents/pkg-<name>.md. The name is lowercase words joined by hyphens, and the Lua
-- module root of the sources is `hecate.<name>` with the hyphens replaced by underscores (ADR 0032:
-- `unicode-data` is `hecate.unicode_data`).
local util = require("lib.util")
local boundaries = require("lib.boundaries")

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
          dir .. "/" .. (name == "hecate" and "hecate" or "hecate-" .. name) .. "-scm-1.rockspec",
          dir .. "/tests",
          ctx.root .. "/.claude/agents/pkg-" .. name .. ".md",
        }
        if not boundaries.valid_name(name) then
          problems[#problems + 1] = ("packages/%s: the name must be lowercase words joined by hyphens"):format(name)
        end
        local module = boundaries.module_name(name)
        if util.is_dir(dir .. "/src/hecate") and name ~= "hecate" and not util.is_dir(dir .. "/src/hecate/" .. module) then
          problems[#problems + 1] = ("packages/%s: the module root must be src/hecate/%s"):format(name, module)
        end
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
