-- Decoding returns Lua integers for integer literals and floats otherwise; `[]`
-- and `{}` keep their kind through markers, so an empty array round-trips.
local json = require("hecate.json")

local value = json.decode('{"count":3,"ratio":0.5,"items":[]}')
print(("%s %s %s %s"):format(math.type(value.count), math.type(value.ratio), json.is_array(value.items), json.encode(value.items)))
-- Prints: integer float true []
