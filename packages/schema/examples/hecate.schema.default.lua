-- A default makes a property optional. A POST or PUT receives a fresh copy of it; a PATCH never
-- does, because an absent attribute of a PATCH means unchanged.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Article = core.class("Article")
function Article.schema()
  return schema.object({
    title = schema.string(),
    tags = schema.default(schema.array(schema.string()), { "draft" }),
  })
end
core.finalise(Article)

local articles = schema.of(Article)

local _, created = articles:build({ title = "Hello" })
print(#created.tags, created.tags[1], schema.sent(created, "tags"))

-- The default is copied: changing it on one instance changes nothing else.
created.tags[1] = "changed"
local _, other = articles:build({ title = "Again" })
print(other.tags[1])

local _, patched = articles:build({ title = "Renamed" }, { method = "PATCH" })
print(patched.tags, schema.sent(patched, "tags"))

-- `validate` never supplies a value; it only checks.
print((schema.object({ tags = schema.default(schema.string(), "x") }):validate({})))
-- Prints: 1	draft	false
-- draft
-- nil	false
-- true
