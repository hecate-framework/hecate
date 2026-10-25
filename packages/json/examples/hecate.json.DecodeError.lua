-- A rejected text raises a `DecodeError` whose context names the reason and the
-- position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[1, 2")
print(("%s %s %d %d"):format(ok, err.context.reason, err.context.line, err.context.column))
-- Prints: false syntax 1 6
