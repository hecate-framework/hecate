-- check-licenses: each directory that holds a VENDORED.md has a LICENSE and an entry in THIRD_PARTY_NOTICES.
-- Rust crates are covered by cargo-deny (deny.toml, security.yml).
local util = require("lib.util")
local licenses = require("lib.licenses")

return {
  description = "vendored third-party code has a LICENSE and is recorded in THIRD_PARTY_NOTICES",
  run = function(ctx)
    local dirs = {}
    for _, path in ipairs(util.walk(ctx.root .. "/packages", "VENDORED.md")) do
      dirs[#dirs + 1] = path:sub(#ctx.root + 2):gsub("/VENDORED%.md$", "")
    end
    table.sort(dirs)
    local f = io.open(ctx.root .. "/THIRD_PARTY_NOTICES", "rb")
    local notices = f and f:read("a") or ""
    if f then f:close() end
    local problems = licenses.check(dirs, function(p) return util.exists(ctx.root .. "/" .. p) end, notices)
    return { ok = #problems == 0, problems = problems }
  end,
}
