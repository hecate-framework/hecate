-- The router reads the raw path of a request: each segment is decoded on its
-- own and dot segments are resolved first.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/files/{name}", name = "file" },
  { method = "GET", path = "/docs/{topic}/index", name = "index" },
})

-- An encoded slash is data: it does not split the segment.
print(routes:match("GET", "/files/reports%2F2026.pdf").parameters.name)
-- Prints: reports/2026.pdf

-- Dot segments never climb above the root and are resolved before matching.
print(routes:match("GET", "/docs/x/../y/./index").parameters.topic)
-- Prints: y
print(routes:match("GET", "/../../files/a").parameters.name)
-- Prints: a

-- A path that cannot be read is a 400, not a 404.
local bad = routes:match("GET", "/files/%zz")
print(bad.status, bad.reason)
-- Prints: 400	malformed_percent_encoding
