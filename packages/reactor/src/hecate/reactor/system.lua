-- Capability queries about the running system (ADR 0023, "Linux first, enforced": the policy in `kernel` asks the
-- mechanism in `reactor`, the only package that reaches libuv).
global <const> require, math

local uv = require("luv")

--- Capability queries about the running system.
---@class hecate.reactor.system
local M = {}

--- Name of the operating system, as libuv reports it (`uname` sysname): `"Linux"`, `"Darwin"`, `"Windows_NT"`, ...
--- Does not suspend.
---@return string name
function M.system_name()
  return uv.os_uname().sysname
end

--- Number of processing units this process may use, at least 1 (libuv `uv_available_parallelism`): the default count
--- of workers of a multi-process server. Does not suspend.
---@return integer count
function M.available_parallelism()
  local count = uv.available_parallelism()
  return math.max(1, math.tointeger(count) or 1)
end

return M
