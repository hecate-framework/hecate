-- The options of a reporter: a table with a `write` function and the keys the reporter knows. Shared by the four
-- reporters so that they are all built the same way.
global <const> require, type, error, pairs, tostring, io

local core = require("hecate.core")

--- The options every reporter accepts.
---@class hecate.test.ReporterOptions
---@field write? fun(text: string)  receives the output; default `io.stdout:write` (the console and JSON-lines reporters flush it)

---@class hecate.test.reporters.options
local M = {}

--- Checks the options of a reporter and returns them (an empty table for `nil`).
---
--- Raises `hecate.core.ArgumentError` when `options` is not a table, holds a key that is not in `known` (nor `write`),
--- or when `write` is not a function.
---@param name string  the reporter, for the message
---@param options any
---@param known? table<string, true>  the other keys the reporter accepts
---@return table options
function M.check(name, options, known)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("test.%s: expects an options table, got %s"):format(name, type(options))), 4)
  end
  for key in pairs(options) do
    if key ~= "write" and not (known and known[key]) then
      error(core.ArgumentError(("test.%s: unknown option %s"):format(name, tostring(key))), 4)
    end
  end
  if options.write ~= nil and type(options.write) ~= "function" then
    error(core.ArgumentError(("test.%s: write must be a function of a text"):format(name)), 4)
  end
  return options
end

--- The function a reporter writes with: `options.write`, else `io.stdout:write`, flushed when `flush` is true.
---@param options table
---@param flush? boolean
---@return fun(text: string)
function M.writer(options, flush)
  if options.write then return options.write end
  return function(text)
    io.stdout:write(text)
    if flush then io.stdout:flush() end
  end
end

return M
