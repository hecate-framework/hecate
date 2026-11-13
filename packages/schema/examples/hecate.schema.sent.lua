-- For a PATCH, `schema.sent` tells an attribute left unchanged from one that
-- was cleared.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Profile = core.class("Profile", nil, { implements = { schema.Representable } })
function Profile.schema()
  return schema.object({
    name = schema.string(),
    bio = schema.optional(schema.nullable(schema.string())),
  })
end
core.finalise(Profile)

local profiles = schema.of(Profile)

-- The attribute is absent: unchanged.
local _, unchanged = profiles:build({ name = "Ada" }, { method = "PATCH" })
print(unchanged.bio, schema.sent(unchanged, "bio"))
-- Prints: nil	false

-- The attribute is an explicit null: cleared. Both leave `bio` nil.
local _, cleared = profiles:build({ bio = json.null }, { method = "PATCH" })
print(cleared.bio, schema.sent(cleared, "bio"), schema.sent(cleared, "name"))
-- Prints: nil	true	false

-- A PATCH relaxes the required properties of the top-level object only.
print((profiles:build({}, { method = "POST" })))
-- Prints: false
print((profiles:build({}, { method = "PATCH" })))
-- Prints: true

-- A value that `build` did not make has sent nothing, and `sent` does not
-- raise.
print(schema.sent({ name = "Ada" }, "name"))
-- Prints: false
