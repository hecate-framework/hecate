-- A synchronous in-memory sink, for tests and for inspection.
global <const> require, error, tostring, table, math

local core = require("hecate.core")

--- A sink that keeps records in memory. `write` never suspends.
---@class hecate.log.MemorySink
---@overload fun(options?: hecate.log.MemorySinkOptions): hecate.log.MemorySink
local MemorySink = core.class("MemorySink")

--- Options of `MemorySink`.
---@class hecate.log.MemorySinkOptions
---@field capacity? integer  most records kept; the oldest are dropped beyond it (default: unbounded)

--- Initialises a sink.
---
--- Raises `hecate.core.ArgumentError` if `capacity` is not a positive integer.
---@param options? hecate.log.MemorySinkOptions
function MemorySink:init(options)
  local capacity = options and options.capacity
  if capacity ~= nil and (math.type(capacity) ~= "integer" or capacity < 1) then
    error(core.ArgumentError(("invalid capacity %s: expected a positive integer"):format(tostring(capacity))), 2)
  end
  self._capacity = capacity
  self._records = {}
  self._dropped = 0
end

--- Keeps a record.
---@param record hecate.log.Record
function MemorySink:write(record)
  local records = self._records
  records[#records + 1] = record
  if self._capacity and #records > self._capacity then
    table.remove(records, 1)
    self._dropped = self._dropped + 1
  end
end

--- Returns a copy of the list of kept records, oldest first.
---@return hecate.log.Record[]
function MemorySink:records() return table.move(self._records, 1, #self._records, 1, {}) end

--- Returns how many records were dropped because of the capacity.
---@return integer
function MemorySink:dropped() return self._dropped end

--- Forgets every kept record.
function MemorySink:clear() self._records = {} end

return core.finalise(MemorySink)
