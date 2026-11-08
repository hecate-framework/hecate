-- Build an instance of a class from the texts of a query string: convert, validate, apply defaults.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Filter = core.class("Filter", nil, { implements = { schema.Representable } })
function Filter.schema()
  return schema.object({
    status = schema.default(schema.string(), "open"),
    limit = schema.default(schema.integer({ minimum = 1, maximum = 100 }), 20),
    tags = schema.optional(schema.array(schema.string())),
    archived = schema.optional(schema.boolean()),
  })
end
core.finalise(Filter)

local filters = schema.of(Filter)

-- Every value of a query string is a text: `coerce = true` converts it before building.
local _, filter = filters:build({ limit = "5", tags = "a,b", archived = "true" }, { coerce = true })
print(core.is_instance_of(filter, Filter), filter.status, filter.limit, #filter.tags, filter.archived)
print(schema.sent(filter, "limit"), schema.sent(filter, "status"))

-- A text that cannot be converted is a violation with the path of the parameter.
local ok, violations = filters:build({ limit = "many" }, { coerce = true })
print(ok, violations[1].path, violations[1].code)
-- Prints: true	open	5	2	true
-- true	false
-- false	/limit	coercion
