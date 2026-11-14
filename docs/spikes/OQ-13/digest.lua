-- The only sha256 interface the CLI uses. Callers never require a hash rock directly.
--   digest.sha256(data)        -> 64 lowercase hexadecimal characters
--   digest.sha256_file(path)   -> the same, for the content of a file
-- The rock behind it is chosen in ONE place: digest_backend.lua.
local backend = require("digest_backend")

local M = {}

---@param data string
---@return string hex
function M.sha256(data)
  assert(type(data) == "string", "digest.sha256: string expected")
  return backend.sha256(data)
end

---@param path string
---@return string? hex
---@return string? err
function M.sha256_file(path)
  if backend.sha256_file then return backend.sha256_file(path) end
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("a")
  f:close()
  return M.sha256(data)
end

M.backend_name = backend.name

return M
