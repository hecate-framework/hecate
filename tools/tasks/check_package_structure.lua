-- check-package-structure: every packages/<name> has README.md, CLAUDE.md, a rockspec,
-- tests/ and an agent in .claude/agents/pkg-<name>.md. The name is lowercase words joined by hyphens, and the Lua
-- module root of the sources is `hecate.<name>` with the hyphens replaced by underscores (ADR 0032:
-- `unicode-data` is `hecate.unicode_data`).
--
-- A package whose README has `| Kind | actions |` (`packages/actions`, lib/package_kind.lua) is not a Lua rock: it is
-- exempt from the rockspec, the tests/ directory and the module root, and must instead have no rockspec and at least
-- one `<directory>/action.yml`. For every package the `Repository` row names the mirror `hecate-framework/hecate-<name>`
-- (ADR 0017), except the meta-package `hecate`, which is built from the monorepo.
local util = require("lib.util")
local boundaries = require("lib.boundaries")
local package_kind = require("lib.package_kind")

return {
  description = "every package has README, CLAUDE.md, rockspec, tests/ and its agent",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      local dir = pkgs .. "/" .. name
      if util.exists(dir .. "/.") and name ~= "README.md" then
        local f = io.open(dir .. "/README.md", "rb")
        local readme = f and f:read("a") or ""
        if f then f:close() end
        local kind = package_kind.of(readme)
        local rockspec = dir .. "/" .. (name == "hecate" and "hecate" or "hecate-" .. name) .. "-scm-1.rockspec"
        local required = {
          dir .. "/README.md",
          dir .. "/CLAUDE.md",
          ctx.root .. "/.claude/agents/pkg-" .. name .. ".md",
        }
        if kind == "rock" then
          required[#required + 1] = rockspec
          required[#required + 1] = dir .. "/tests"
        elseif not package_kind.known(readme) then
          problems[#problems + 1] = ("packages/%s/README.md: unknown Kind `%s`"):format(name, kind)
        else
          if util.exists(rockspec) then
            problems[#problems + 1] = ("packages/%s: a package of kind %s is not a rock and has no rockspec"):format(name, kind)
          end
          local has_action = false
          for _, entry in ipairs(util.list_dir(dir)) do
            if util.exists(dir .. "/" .. entry .. "/action.yml") then has_action = true end
          end
          if not has_action then problems[#problems + 1] = ("packages/%s: no <directory>/action.yml"):format(name) end
        end
        if name ~= "hecate" and readme ~= "" and not readme:find("| Repository | read-only mirror `hecate-framework/hecate-" .. name .. "`", 1, true) then
          problems[#problems + 1] = ("packages/%s/README.md: the Repository row must name the mirror hecate-framework/hecate-%s"):format(name, name)
        end
        if not boundaries.valid_name(name) then
          problems[#problems + 1] = ("packages/%s: the name must be lowercase words joined by hyphens"):format(name)
        end
        local module = boundaries.module_name(name)
        if kind == "rock" and util.is_dir(dir .. "/src/hecate") and name ~= "hecate" and not util.is_dir(dir .. "/src/hecate/" .. module) then
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
