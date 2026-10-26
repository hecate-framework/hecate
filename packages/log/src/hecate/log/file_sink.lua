-- A sink that appends JSON lines to a file.
global <const> require, type, error, io, tostring

local core = require("hecate.core")
local JsonLinesSink = require("hecate.log.json_lines_sink")

--- A sink appending one JSON object per record to a file. Writes are synchronous (they block the
--- calling computation for the duration of the write); asynchronous flushing is a later step.
---@class hecate.log.FileSink
---@overload fun(options: hecate.log.FileSinkOptions): hecate.log.FileSink
local FileSink = core.class("FileSink")

--- Options of `FileSink`.
---@class hecate.log.FileSinkOptions
---@field path string  file to append to; created when missing

--- Opens the file.
---
--- Raises `hecate.core.ArgumentError` if `path` is not a string, `hecate.core.Error` if it cannot be opened.
---@param options hecate.log.FileSinkOptions
function FileSink:init(options)
  if type(options) ~= "table" or type(options.path) ~= "string" or options.path == "" then
    error(core.ArgumentError("log.FileSink: expects an options table with a path"), 2)
  end
  local handle, message = io.open(options.path, "ab")
  if not handle then error(core.Error(("log.FileSink: cannot open log file: %s"):format(tostring(message))), 2) end
  handle:setvbuf("line")
  self._handle = handle
  self._lines = JsonLinesSink({
    output = function(line)
      local ok, reason = handle:write(line)
      if not ok then error(core.Error(("log.FileSink: cannot write to the log file: %s"):format(tostring(reason))), 0) end
    end,
  })
end

--- Writes a record as one line. Raises `hecate.core.Error` if the write fails (disk full, closed descriptor);
--- a `Logger` counts it in `failures()` and goes on.
---@param record hecate.log.Record
function FileSink:write(record)
  if not self._handle then return end
  self._lines:write(record)
end

--- Flushes and closes the file; later writes are ignored.
function FileSink:close()
  if self._handle then
    self._handle:close()
    self._handle = nil
  end
end

return core.finalise(FileSink)
