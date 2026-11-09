-- hecate.kernel: the application. So far: the chain of responsibility.
global <const> require

--- The application kernel.
---@class hecate.kernel
---@field chain hecate.kernel.chain  composes filters around an action
local kernel = {}

kernel.chain = require("hecate.kernel.chain")

return kernel
