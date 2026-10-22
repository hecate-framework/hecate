-- Encoding keeps the difference between integers and floats, writes `json.null`
-- explicitly, and orders members with `canonical` so that the text is stable.
local json = require("hecate.json")

print(json.encode({ b = 1, a = 2.0, c = json.null }, { canonical = true }))
-- Prints: {"a":2.0,"b":1,"c":null}
