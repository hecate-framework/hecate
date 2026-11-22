-- Backend over the `plc` rock (pure Lua, MIT): nothing to compile, one-shot only (a file is read whole), about
-- 2.6 MB/s, which suits the archives of a toolchain. The fallback of ADR 0028.
-- Raises when the rock is not installed, so that `digest_backend.select` reports the missing rocks.
global <const> require, string

local sha2 = require("plc.sha2")

return {
  name = "plc",
  sha256 = function(data)
    return (sha2.hash256(data):gsub(".", function(character) return string.format("%02x", character:byte()) end))
  end,
}
