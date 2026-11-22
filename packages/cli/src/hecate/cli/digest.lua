-- The only SHA-256 interface of the CLI (ADR 0028): callers never require a hash rock. The rock behind it is chosen
-- in one place, `hecate.cli.internal.digest_backend`: the `digest` rock when it is installed (C, fast, streams), the
-- pure-Lua `plc` rock otherwise.
global <const> require, type, io, assert

local backend = require("hecate.cli.internal.digest_backend")

---@class hecate.cli.Digest
---@field backend_name string  the rock in use, "digest" or "plc"
---@field sha256 fun(data: string): string  64 lowercase hexadecimal characters
---@field sha256_file fun(path: string): string?, string?  the same for the content of a file; `nil` and a message when it cannot be read

--- Builds the interface over a backend: `{ name, sha256(data), sha256_file?(path) }`. A backend without
--- `sha256_file` is read whole.
---@param chosen hecate.cli.DigestBackend
---@return hecate.cli.Digest
local function using(chosen)
  local self = { backend_name = chosen.name }
  function self.sha256(data)
    assert(type(data) == "string", "digest.sha256: string expected")
    return chosen.sha256(data)
  end
  function self.sha256_file(path)
    if chosen.sha256_file then return chosen.sha256_file(path) end
    local file, message = io.open(path, "rb")
    if not file then return nil, message end
    local data = file:read("a")
    file:close()
    return chosen.sha256(data)
  end
  return self
end

--- SHA-256 of the CLI over the best backend installed. `using` builds the same interface over another backend (the
--- contract test runs every backend through it).
---@class hecate.cli.digest : hecate.cli.Digest
local M = using(backend.select())
M.using = using

return M
