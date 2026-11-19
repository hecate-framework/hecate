-- check-licenses: each directory that holds a VENDORED.md has a LICENSE and an entry in THIRD_PARTY_NOTICES, a
-- directory named vendor or third_party without a VENDORED.md is reported, and the paths that THIRD_PARTY_NOTICES
-- names must exist; the SHA-256 table of each VENDORED.md matches the files; the licence page of each Rust native module
-- (packages/<name>/native/LICENSES-rust.md, gen-rust-licences) exists and records the digest of the current Cargo.lock
-- (the complete check, with cargo, is `gen-rust-licences --check`). Rust crates are covered by cargo-deny (deny.toml,
-- security.yml).
local util = require("lib.util")
local licenses = require("lib.licenses")
local sha256 = require("lib.sha256")
local rust = require("lib.rust_licences")

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
    local function read(path)
      local file = io.open(ctx.root .. "/" .. path, "rb")
      if not file then return nil end
      local data = file:read("a")
      file:close()
      return data
    end
    -- A directory whose licence text is not named LICENSE (the SIL OFL texts of fonts, `OFL-*.txt`) says so in its table.
    local licence_files = {}
    for _, dir in ipairs(dirs) do licence_files[dir] = licenses.licence_files(licenses.digests(read(dir .. "/VENDORED.md") or "")) end
    local problems = licenses.check(dirs, function(p) return util.exists(ctx.root .. "/" .. p) end, notices, unrecorded,
      licence_files)
    -- The vendored copies stay byte-identical to upstream: re-verify the digests of every VENDORED.md.
    for _, dir in ipairs(dirs) do
      for _, problem in ipairs(licenses.verify_text(dir, read(dir .. "/VENDORED.md") or "", read, sha256.hex)) do
        problems[#problems + 1] = problem
      end
    end
    -- A change of a Cargo.lock forces the regeneration of the licence page of its module.
    for _, package in ipairs(util.list_dir(ctx.root .. "/packages")) do
      local directory = ("packages/%s/native"):format(package)
      local problem = rust.check_page(directory, read(directory .. "/Cargo.lock"), read(directory .. "/LICENSES-rust.md"),
        sha256.hex)
      if problem then problems[#problems + 1] = problem end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
