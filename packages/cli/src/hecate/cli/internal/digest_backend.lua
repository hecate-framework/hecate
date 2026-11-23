-- Switch point of ADR 0028: the one module that knows which rocks provide SHA-256. To use another rock, change the
-- list below and the dependency of the rockspec; no caller changes.
global <const> require, pcall, error, ipairs

---@class hecate.cli.DigestBackend
---@field name string  the rock, "digest"
---@field sha256 fun(data: string): string  64 lowercase hexadecimal characters
---@field sha256_file? fun(path: string): string?, string?  streams the file; absent when the rock cannot (the file is read whole)

---@class hecate.cli.internal.digest_backend
local M = {}

--- The backends in order of preference: module names under `hecate.cli.internal`.
M.CANDIDATES = { "digest_backend_digest" }

--- The first backend whose rock loads. Raises an error naming the rocks when none does.
---@return hecate.cli.DigestBackend
function M.select()
  for _, name in ipairs(M.CANDIDATES) do
    local ok, backend = pcall(require, "hecate.cli.internal." .. name)
    if ok then return backend end
  end
  error("hecate.cli: no SHA-256 implementation: install the `digest` rock: luarocks install digest", 0)
end

return M
