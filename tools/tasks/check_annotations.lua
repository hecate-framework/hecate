-- check-annotations: LuaLS annotations of the exported symbols in packages/**/src
-- (coding-standards.md "Annotations for the reference", ADR 0018). The rules, and what a text
-- scan can and cannot see, are documented in tools/lib/annotations.lua.
-- Append `-- annotations-ok` to a definition line to accept a justified exception.
local util = require("lib.util")
local annotations = require("lib.annotations")

return {
  description = "exported symbols of packages/**/src carry LuaLS annotations (@param, @return, @class); "
    .. "nil-for-absence returns are nullable (ADR 0018); `---@async` consistency is not checked yet",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      for _, file in ipairs(util.walk(("%s/%s/src"):format(pkgs, name), ".lua")) do
        local rel = file:sub(#ctx.root + 2)
        if not rel:find("/internal/", 1, true) then
          local f = io.open(file, "rb")
          if f then
            local src = f:read("a")
            f:close()
            for _, hit in ipairs(annotations.scan(src)) do
              problems[#problems + 1] = ("%s:%d: `%s`: %s"):format(rel, hit.line, hit.name, hit.message)
            end
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
