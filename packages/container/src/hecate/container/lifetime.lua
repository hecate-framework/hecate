-- The lifetimes of a service (container.md, "Lifetimes").
global <const> require

local core = require("hecate.core")

--- How long an instance of a service lives: `singleton` as long as the container, `scoped` as long as one service
--- scope, `transient` for the caller only.
---@class hecate.container.Lifetime
---@field singleton hecate.core.EnumerationValue
---@field scoped hecate.core.EnumerationValue
---@field transient hecate.core.EnumerationValue
---@field find fun(self: hecate.container.Lifetime, name: string): hecate.core.EnumerationValue?  the member of that name
---@field contains fun(self: hecate.container.Lifetime, value: any): boolean  whether `value` is a member
local Lifetime = core.enumeration("Lifetime", { "singleton", "scoped", "transient" })

return Lifetime
