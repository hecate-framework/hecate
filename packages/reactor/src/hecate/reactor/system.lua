-- Capability queries about the running system (ADR 0023, "Linux first, enforced": the policy in `kernel` asks the
-- mechanism in `reactor`, the only package that reaches libuv).
global <const> require, math, type, error

local uv = require("luv")
local core = require("hecate.core")
local uv_call = require("hecate.reactor.internal.uv_call")

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

--- Reads the environment variable `name` through libuv (`uv_os_getenv`): its value, or `nil` when it is not set. On
--- Windows libuv reads the wide (UTF-16) environment, so a non-ASCII value arrives as UTF-8 whatever the code page;
--- elsewhere the bytes are those of `os.getenv`. Does not suspend and needs no running reactor (OQ-124).
---
--- Raises `hecate.core.ArgumentError` when `name` is not a string, and `hecate.reactor.IoError` for a libuv failure
--- other than an unset variable.
---@param name string  the variable name
---@return string? value  the value, `nil` when the variable is not set
function M.getenv(name)
  if type(name) ~= "string" then
    error(core.ArgumentError("reactor.getenv: expects a variable name, got " .. type(name)), 2)
  end
  local value, message, code = uv.os_getenv(name)
  if value ~= nil then return value end
  if code == "ENOENT" then return nil end
  -- coverage: off (libuv answers ENOENT for every name that is not set; another failure is not reproducible)
  uv_call.fail("reactor.getenv", "os_getenv", message)
  -- coverage: on
end

return M
