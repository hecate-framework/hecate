-- Helpers that keep a failing assertion from leaking changed module state into the next test.
local M = {}

--- Runs `fn` with the fields of `overrides` set in the table `target`, restores every one of them (to nil when it was
--- absent) even when `fn` raises, then raises the same value again.
---@param target table
---@param overrides table<string, any>
---@param fn fun()
function M.with_fields(target, overrides, fn)
  local saved, present = {}, {}
  for key, value in pairs(overrides) do
    saved[key], present[key] = target[key], target[key] ~= nil
    target[key] = value
  end
  local ok, err = pcall(fn)
  for key in pairs(overrides) do
    if present[key] then target[key] = saved[key] else target[key] = nil end
  end
  if not ok then error(err, 0) end
end

return M
