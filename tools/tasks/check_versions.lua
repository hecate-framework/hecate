-- check-versions: every rockspec is at scm-1 or at the version in VERSION (ADR 0005) and
-- requires "lua >= 5.5, < 5.6". The data rock `hecate-unicode-data` is exempt from the lockstep (ADR 0032): a
-- released rockspec of it is at `<Unicode version>-<revision>`, the Unicode version being the one of its
-- generated tables; the tree itself holds the development version `scm-1` of every package. The `version` field of each
-- top-level module (`hecate.core.version`, ...) equals VERSION, except `unicode` and `unicode-data`.
local util = require("lib.util")
local rockspec = require("lib.rockspec")
local package_kind = require("lib.package_kind")

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
    for _, name in ipairs(package_kind.rocks(ctx.root)) do
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
    local unicode_version = (read(pkgs .. "/unicode-data/src/hecate/unicode_data/init.lua") or ""):match('unicode_version%s*=%s*"([%d%.]+)"')
    for _, name in ipairs(package_kind.rocks(ctx.root)) do
      local rock = name == "hecate" and "hecate" or "hecate-" .. name
      for _, file in ipairs(util.list_dir(pkgs .. "/" .. name)) do
        local version = file:match("^" .. rock:gsub("%p", "%%%0") .. "%-(.+)%.rockspec$")
        local problem = version and rockspec.version_problem(name, version, version and (read(ctx.root .. "/VERSION") or ""):match("%S+") or "", unicode_version)
        if problem then problems[#problems + 1] = ("packages/%s/%s: %s"):format(name, file, problem) end
      end
    end
    -- The `version` field of each top-level module is the version of VERSION (owner decision of 2026-11-25).
    if version then
      for _, name in ipairs(package_kind.rocks(ctx.root)) do
        local module = name:gsub("-", "_")
        local text = not rockspec.version_field_exempt[name]
          and (read(name == "hecate" and (pkgs .. "/hecate/src/hecate/init.lua") or ("%s/%s/src/hecate/%s/init.lua"):format(pkgs, name, module)))
        if text then
          local found = rockspec.module_version(text)
          local rel = name == "hecate" and "packages/hecate/src/hecate/init.lua" or ("packages/%s/src/hecate/%s/init.lua"):format(name, module)
          if not found then
            problems[#problems + 1] = rel .. ': no `version = "' .. version .. '"` field'
          elseif found ~= version then
            problems[#problems + 1] = ("%s: version field is %s, VERSION is %s"):format(rel, found, version)
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
