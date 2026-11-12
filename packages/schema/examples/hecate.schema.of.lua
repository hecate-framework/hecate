-- A class owns the schema of its instances: the interface
-- `schema.Representable` requires a class-level `schema()`, and
-- `schema.of(Class)` uses the class wherever it is a part of another schema.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Representable = schema.Representable

local Address = core.class("Address", nil, { implements = { Representable } })
function Address.schema()
  return schema.object({ street = schema.string(), city = schema.string() })
end
core.finalise(Address)

local User = core.class("User", nil, { implements = { Representable } })
function User.schema()
  return schema.object({ name = schema.string(), address = schema.of(Address) })
end
core.finalise(User)

-- A class that declares the interface without `schema()` cannot be finalised.
local Incomplete = core.class("Incomplete", nil, { implements = { Representable } })
print((pcall(core.finalise, Incomplete)))
-- Prints: false

-- `schema.of` refuses a class that does not declare the interface, even when
-- it has a `schema` function.
local Plain = core.class("Plain")
function Plain.schema() return schema.object({}) end
core.finalise(Plain)
print((pcall(schema.of, Plain)))
-- Prints: false

local ok, user = schema.of(User):build({ name = "Ada", address = { street = "1 Main St", city = "Paris" } })
print(ok, core.is_instance_of(user, User), core.is_instance_of(user.address, Address))
-- Prints: true	true	true

-- The emission names each class once, in `$defs`, and refers to it.
local document = schema.of(User):to_json_schema()
print(document["$ref"], document["$defs"].User.properties.address["$ref"])
-- Prints: #/$defs/User	#/$defs/Address
