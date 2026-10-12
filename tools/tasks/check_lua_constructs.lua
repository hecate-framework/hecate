-- check-lua-constructs: only the 5.5 constructs allowed by ADR 0001.
local util = require("lib.util")
local constructs = require("lib.constructs")

return {
  description = "only the Lua 5.5 constructs allowed by ADR 0001 in packages/**/src",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      for _, file in ipairs(util.walk(("%s/%s/src"):format(pkgs, name), ".lua")) do
        local f = io.open(file, "rb")
        if f then
          local src = f:read("a")
          f:close()
          local rel = file:sub(#ctx.root + 2)
          local allow = name == "core" and rel:find("compat", 1, true) ~= nil
          for _, hit in ipairs(constructs.scan(src, allow)) do
            problems[#problems + 1] = ("%s:%d: %s"):format(rel, hit.line, hit.message)
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
