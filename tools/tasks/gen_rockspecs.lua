-- gen-rockspecs: writes packages/<name>/hecate-<name>-scm-1.rockspec and tests/.gitkeep
-- from the package README (summary line and "Depends on" row). Idempotent.
local util = require("lib.util")

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
        local text = read(readme)
        local summary = text:match("\n> ([^\n]+)")
        local row = text:match("\n| Depends on | ([^\n]*) |")
        if not summary or not row then
          problems[#problems + 1] = ("packages/%s: README lacks summary or 'Depends on' row"):format(name)
        else
          local deps = { '"lua >= 5.5, < 5.6"' }
          for dep in row:gmatch("%[`([%w_]+)`%]") do deps[#deps + 1] = ('"hecate-%s"'):format(dep) end
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
  license = "MIT",
}

dependencies = {
  %s,
}

build = {
  type = "builtin",
  modules = {},
}
]]):format(rock, rock, (summary:gsub('"', '\\"')), table.concat(deps, ",\n  "))
          write(pkgs .. "/" .. name .. "/" .. rock .. "-scm-1.rockspec", spec)
          if not util.exists(pkgs .. "/" .. name .. "/tests") then
            os.execute(('mkdir -p "%s/%s/tests"'):format(pkgs, name))
            write(pkgs .. "/" .. name .. "/tests/.gitkeep", "")
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
