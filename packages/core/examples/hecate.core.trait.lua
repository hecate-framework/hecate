-- A trait adds methods to a class; an interface lists the methods a class
-- must have. Both are checked once, when the class is finalised.
local core = require("hecate.core")

local Comparable = core.interface("Comparable", { "compare" })
local Ordered = core.trait("Ordered", {
  less_than = function(self, other) return self:compare(other) < 0 end,
}, { requires = { "compare" } })

local Money = core.class("Money", nil, {
  traits = { Ordered }, implements = { Comparable },
})
function Money:init(cents) self.cents = cents end
function Money:compare(other) return self.cents - other.cents end
core.finalise(Money)

print(Money(150):less_than(Money(200)), core.implements(Money, Comparable))
-- Prints: true	true

-- A class that misses a required method fails at finalisation, not later.
local Broken = core.class("Broken", nil, { implements = { Comparable } })
local ok, err = pcall(core.finalise, Broken)
print(ok, core.name(err))
-- Prints: false	ConformanceError

-- A value class is frozen after `init` and compared by value.
local Point = core.value_class("Point")
function Point:init(x, y) self.x, self.y = x, y end
core.finalise(Point)
print(Point(1, 2) == Point(1, 2))
-- Prints: true
local written, refusal = pcall(function() Point(1, 2).x = 3 end)
print(written, core.name(refusal))
-- Prints: false	ConformanceError
