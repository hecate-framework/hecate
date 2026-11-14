-- Backend over the `plc` rock (pure Lua, MIT): embeds as Lua source, one-shot only.
local sha2 = require("plc.sha2")

local function hex(raw)
  return (raw:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

return {
  name = "plc",
  sha256 = function(data) return hex(sha2.hash256(data)) end,
}
