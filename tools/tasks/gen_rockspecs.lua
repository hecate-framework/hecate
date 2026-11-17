-- gen-rockspecs: writes packages/<name>/hecate-<name>-scm-1.rockspec and tests/.gitkeep
-- from the package README (summary line and "Depends on" row). Idempotent; a `build` table that was edited by hand
-- (native modules) is kept.
local util = require("lib.util")
local rockspec = require("lib.rockspec")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

return {
  description = "generate per-package rockspecs and tests/ skeleton from READMEs",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      local readme = pkgs .. "/" .. name .. "/README.md"
      if util.exists(readme) then
        local text = read(readme):gsub("\r\n", "\n")
        local summary = text:match("\n> ([^\n]+)")
        local row = text:match("\n| Depends on | ([^\n]*) |")
        if not summary or not row then
          problems[#problems + 1] = ("packages/%s: README lacks summary or 'Depends on' row"):format(name)
        else
          local deps = { '"lua >= 5.5, < 5.6"' }
          for _, dep in ipairs(rockspec.readme_dependencies(row)) do deps[#deps + 1] = rockspec.dependency_string(dep) end
          local rock = name == "hecate" and "hecate" or "hecate-" .. name
          local spec = ([[
rockspec_format = "3.0"
package = "%s"
version = "scm-1"

source = {
  url = "git+https://github.com/hecate-framework/%s.git",
}

description = {
  summary = "%s",
  homepage = "https://github.com/hecate-framework/hecate",
  license = "%s",
}

dependencies = {
  %s,
}

build = {
  type = "builtin",
  modules = {},
}
]]):format(rock, rock, (summary:gsub('"', '\\"')), rockspec.license(name), table.concat(deps, ",\n  "))
          local path = pkgs .. "/" .. name .. "/" .. rock .. "-scm-1.rockspec"
          local existing = util.exists(path) and read(path) or nil
          write(path, rockspec.keep_build(spec, existing))
          if not util.exists(pkgs .. "/" .. name .. "/tests") then
            util.mkdir(pkgs .. "/" .. name .. "/tests")
            write(pkgs .. "/" .. name .. "/tests/.gitkeep", "")
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
