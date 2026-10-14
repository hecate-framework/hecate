-- Declares a class with a method, finalises it, then uses it.
local core = require("hecate.core")

local Money = core.class("Money")

function Money:init(amount)
  self.amount = amount
end

function Money:double()
  return Money(self.amount * 2)
end

core.finalise(Money)

print(Money(21):double().amount)
-- Prints: 42
