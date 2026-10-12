-- check-rockspecs: runs `luarocks lint` on every package rockspec and checks that each
-- declared hecate-* dependency is an existing package.
local util = require("lib.util")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "luarocks lint on every rockspec; dependencies name existing packages",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    local known = {}
    local names = util.list_dir(pkgs)
    for _, name in ipairs(names) do known[name == "hecate" and "hecate" or "hecate-" .. name] = true end
    for _, name in ipairs(names) do
      local rock = name == "hecate" and "hecate" or "hecate-" .. name
      local path = ("%s/%s/%s-scm-1.rockspec"):format(pkgs, name, rock)
      local text = read(path)
      if text then
        local out, ok = util.capture(('luarocks lint "%s" 2>&1'):format(path))
        if not ok then problems[#problems + 1] = ("%s: luarocks lint: %s"):format(rock, out) end
        for dep in text:gmatch('"(hecate[%w-]*)"') do
          if not known[dep] then problems[#problems + 1] = ("%s: unknown dependency %s"):format(rock, dep) end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
