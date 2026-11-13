-- An enumeration of `core` is represented in JSON by the name of its members.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Status = core.enumeration("Status", { "active", "disabled", "pending" })
local account = schema.object({ status = schema.enumeration(Status) })

print((account:validate({ status = "active" })))
-- Prints: true

-- Only the names are accepted, never the member itself.
local _, violations = account:validate({ status = "Active" })
local violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
-- Prints: /status	enum	active disabled pending

-- `build` replaces the name by the member.
local _, built = account:build({ status = "disabled" })
print(built.status == Status.disabled)
-- Prints: true

local emitted = account:to_json_schema().properties.status
print(emitted.type, #emitted.enum)
-- Prints: string	3
