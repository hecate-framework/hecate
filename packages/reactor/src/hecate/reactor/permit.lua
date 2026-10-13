-- Permit: the right to hold a share of a synchronisation primitive (a semaphore unit, a
-- mutex, a monitor). Releasing it is idempotent and happens automatically when the permit
-- is closed, so `local permit <close> = mutex:lock()` is exception- and cancellation-safe
-- (reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers).
global <const> require

local core = require("hecate.core")

---@class hecate.reactor.Permit
---@overload fun(release: fun()): hecate.reactor.Permit
local Permit = core.class("Permit")

--- Creates a permit whose release runs `release` once.
---@param release fun()
function Permit:init(release)
  self._release = release
  self._held = true
end

--- Returns whether the permit is still held.
---@return boolean
function Permit:is_held() return self._held end

--- Gives the permit back. Releasing a released permit does nothing. Never suspends.
function Permit:release()
  if not self._held then return end
  self._held = false
  local release = self._release
  self._release = nil
  release()
end

--- Closing a permit releases it (`local permit <close> = ...`).
function Permit:__close() self:release() end

return core.finalise(Permit)
