-- check-versions: every rockspec is at scm-1 or at the version in VERSION (ADR 0005) and
-- requires "lua >= 5.5, < 5.6".
local util = require("lib.util")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "rockspec versions agree with VERSION; lua >= 5.5, < 5.6 everywhere",
  run = function(ctx)
    local problems = {}
    local version = (read(ctx.root .. "/VERSION") or ""):match("%S+")
    if not version then problems[#problems + 1] = "VERSION is missing or empty" end
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      local rock = name == "hecate" and "hecate" or "hecate-" .. name
      local path = ("%s/%s/%s-scm-1.rockspec"):format(pkgs, name, rock)
      local text = read(path)
      if text then
        local rel = ("packages/%s/%s-scm-1.rockspec"):format(name, rock)
        if not text:find('"lua >= 5.5, < 5.6"', 1, true) then
          problems[#problems + 1] = rel .. ': missing dependency "lua >= 5.5, < 5.6"'
        end
        if not text:find('\npackage = "' .. rock .. '"', 1, true) then
          problems[#problems + 1] = rel .. ": package field is not '" .. rock .. "'"
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
