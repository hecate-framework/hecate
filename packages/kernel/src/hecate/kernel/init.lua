-- hecate.kernel: the application. So far: the chain of responsibility.
global <const> require

--- The application kernel.
---@class hecate.kernel
---@field chain hecate.kernel.chain  composes filters around an action
---@field results hecate.kernel.results  serialises the result of an action into a Response
---@field problems hecate.kernel.problems  maps errors and routing failures to problem details responses
local kernel = {}

kernel.chain = require("hecate.kernel.chain")
kernel.results = require("hecate.kernel.results")
kernel.problems = require("hecate.kernel.problems")

return kernel
