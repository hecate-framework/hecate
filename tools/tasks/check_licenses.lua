-- check-licenses: each directory that holds a VENDORED.md has a LICENSE and an entry in THIRD_PARTY_NOTICES, a
-- directory named vendor or third_party without a VENDORED.md is reported, and the paths that THIRD_PARTY_NOTICES
-- names must exist. Rust crates are covered by cargo-deny (deny.toml, security.yml).
local util = require("lib.util")
local licenses = require("lib.licenses")

local function relative(root, path) return (path:gsub("\\", "/"):sub(#root + 2)) end

return {
  description = "vendored third-party code has a LICENSE and is recorded in THIRD_PARTY_NOTICES",
  run = function(ctx)
    local dirs, marked = {}, {}
    for _, path in ipairs(util.walk(ctx.root .. "/packages", "VENDORED.md")) do
      local dir = relative(ctx.root, path):gsub("/VENDORED%.md$", "")
      dirs[#dirs + 1] = dir
      marked[dir] = true
    end
    table.sort(dirs)
    local unrecorded = {}
    for _, path in ipairs(util.walk(ctx.root .. "/packages", "")) do
      local dir = licenses.vendor_directory(relative(ctx.root, path))
      if dir and not marked[dir] and not unrecorded[dir] then
        unrecorded[dir] = true
        unrecorded[#unrecorded + 1] = dir
      end
    end
    table.sort(unrecorded)
    local f = io.open(ctx.root .. "/THIRD_PARTY_NOTICES", "rb")
    local notices = f and f:read("a") or ""
    if f then f:close() end
    local problems = licenses.check(dirs, function(p) return util.exists(ctx.root .. "/" .. p) end, notices, unrecorded)
    return { ok = #problems == 0, problems = problems }
  end,
}
