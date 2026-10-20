-- A rejected text raises a `DecodeError` whose context names the reason and the position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, '{"a":1,"a":2}')
print(ok, err.context.reason, err.context.line, err.context.column)
-- Prints: false	duplicate_key	1	8
