-- A class owns the schema of its instances: the interface `schema.HasSchema` requires a class-level `schema()`, and
-- `schema.of(Class)` uses the class wherever it is a part of another schema.
local core = require("hecate.core")
local schema = require("hecate.schema")

local HasSchema = schema.HasSchema

local Address = core.class("Address", nil, { implements = { HasSchema } })
function Address.schema()
  return schema.object({ street = schema.string(), city = schema.string() })
end
core.finalise(Address)

local User = core.class("User", nil, { implements = { HasSchema } })
function User.schema()
  return schema.object({ name = schema.string(), address = schema.of(Address) })
end
core.finalise(User)

-- A class that declares the interface without `schema()` cannot be finalised.
local Incomplete = core.class("Incomplete", nil, { implements = { HasSchema } })
print((pcall(core.finalise, Incomplete)))

local ok, user = schema.of(User):build({ name = "Ada", address = { street = "1 Main St", city = "Paris" } })
print(ok, core.is_instance_of(user, User), core.is_instance_of(user.address, Address))

-- The emission names each class once, in `$defs`, and refers to it.
local document = schema.of(User):to_json_schema()
print(document["$ref"], document["$defs"].User.properties.address["$ref"])
-- Prints: false
-- true	true	true
-- #/$defs/User	#/$defs/Address
