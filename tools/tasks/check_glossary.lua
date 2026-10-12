-- check-glossary: discouraged identifiers in packages/**/src (docs/glossary.md, ADR 0004).
-- Append `-- glossary-ok` to a line to accept a justified exception.
local util = require("lib.util")
local glossary = require("lib.glossary")

return {
  description = "deny-list of discouraged identifiers in packages/**/src (glossary)",
  run = function(ctx)
    local problems = {}
    local pkgs = ctx.root .. "/packages"
    for _, name in ipairs(util.list_dir(pkgs)) do
      for _, file in ipairs(util.walk(("%s/%s/src"):format(pkgs, name), ".lua")) do
        local f = io.open(file, "rb")
        if f then
          local src = f:read("a")
          f:close()
          for _, hit in ipairs(glossary.scan(src)) do
            problems[#problems + 1] = ("%s:%d: '%s' is discouraged; use '%s' (docs/glossary.md)"):format(
              file:sub(#ctx.root + 2), hit.line, hit.ident, hit.preferred)
          end
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
