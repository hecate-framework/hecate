-- Backend over the `digest` rock (C, MIT AND BSD-3-Clause): fast, streams files in chunks, no other rock.
-- Raises when the rock is not installed, so that `digest_backend.select` falls through to the next one.
global <const> require, io

---@class hecate.cli.DigestRock
---@field sha256hex fun(data: string): string
---@field new fun(algorithm: string): { add: fun(self: any, chunk: string), hexdigest: fun(self: any): string }

-- The rock is named through a variable: LuaLS would resolve the literal "digest" to this package's `hecate.cli.digest`.
local rock_name = "digest"
---@type hecate.cli.DigestRock
local digest = require(rock_name)

return {
  name = "digest",
  sha256 = function(data) return digest.sha256hex(data) end,
  sha256_file = function(path)
    local file, message = io.open(path, "rb")
    if not file then return nil, message end
    local context = digest.new("sha256")
    for chunk in function() return file:read(65536) end do context:add(chunk) end
    file:close()
    return context:hexdigest()
  end,
}
