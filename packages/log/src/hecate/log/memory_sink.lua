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
    error(core.ArgumentError(("log.MemorySink: invalid capacity %s: expected a positive integer"):format(tostring(capacity))), 2)
  end
  self._capacity = capacity
  self._records = {} -- a ring when `capacity` is set: `_head` is the oldest, `_count` the number kept
  self._head, self._count = 1, 0
  self._dropped = 0
end

--- Keeps a record.
---@param record hecate.log.Record
function MemorySink:write(record)
  local capacity = self._capacity
  if capacity and self._count == capacity then
    self._records[self._head] = record
    self._head = self._head % capacity + 1
    self._dropped = self._dropped + 1
    return
  end
  self._count = self._count + 1
  self._records[self._count] = record -- below capacity the ring has not wrapped: `_head` is 1
end

--- Returns a copy of the list of kept records, oldest first.
---@return hecate.log.Record[]
function MemorySink:records()
  local records, head, count = self._records, self._head, self._count
  local copy = table.move(records, head, count, 1, {})
  if head > 1 then table.move(records, 1, head - 1, count - head + 2, copy) end
  return copy
end

--- Returns how many records were dropped because of the capacity.
---@return integer
function MemorySink:dropped() return self._dropped end

--- Forgets every kept record.
function MemorySink:clear()
  self._records = {}
  self._head, self._count = 1, 0
end

return core.finalise(MemorySink)
