-- The ambient log context: fields bound to the running computation through the scope-local
-- context of the reactor (ADR 0025), inherited by what it forks or detaches.
global <const> require, pairs, pcall, type

local reactor = require("hecate.reactor")

local KEY = {}

local M = {}

--- Returns the fields bound by `bind` in the running computation, or `nil` (also outside a reactor).
---@return table?
function M.fields()
  local ok, fields = pcall(reactor.local_value, KEY)
  if ok and type(fields) == "table" then return fields end
  return nil
end

--- Runs `fn(...)` with `fields` added to the ambient context (`fields` wins over the outer ones).
---@param fields table
---@param fn fun(...): ...
---@param ... any
---@return any ...
function M.bind(fields, fn, ...)
  local merged = {}
  local outer = M.fields()
  if outer then for key, value in pairs(outer) do merged[key] = value end end
  for key, value in pairs(fields) do merged[key] = value end
  return reactor.with_local(KEY, merged, fn, ...)
end

return M
