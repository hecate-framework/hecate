-- A sink that renders each record as one human-readable line.
global <const> require, type, pairs, error, next, tostring, string, table, os, math, ipairs

local core = require("hecate.core")
local Secret = require("hecate.log.secret")

--- Longest rendering of one value; beyond it the text is cut.
local MAX_VALUE = 200

--- A sink that writes `timestamp severity [logger] message key=value ...` lines to a function.
---@class hecate.log.ConsoleSink
---@overload fun(options: hecate.log.ConsoleSinkOptions): hecate.log.ConsoleSink
local ConsoleSink = core.class("ConsoleSink")

--- Options of `ConsoleSink`.
---@class hecate.log.ConsoleSinkOptions
---@field output fun(line: string)  receives each line, newline included; it must not suspend

--- Initialises a sink.
---
--- Raises `hecate.core.ArgumentError` if `output` is not a function.
---@param options hecate.log.ConsoleSinkOptions
function ConsoleSink:init(options)
  if type(options) ~= "table" or type(options.output) ~= "function" then
    error(core.ArgumentError("log.ConsoleSink: expects an options table with an output function"), 2)
  end
  self._output = options.output
end

--- Escapes the control characters of a text, so that it stays on one line.
---@param text string
---@return string
local function escape(text)
  return (text:gsub("%c", function(c) return ("\\x%02x"):format(c:byte()) end))
end

--- Renders a value on one line; secrets are redacted, control characters are escaped.
---@param value any
---@return string
local function render(value)
  local text
  if core.is_instance_of(value, Secret) then
    text = Secret.REDACTED
  elseif type(value) == "table" then
    text = "{...}"
  else
    text = tostring(value)
  end
  text = escape(text)
  if #text > MAX_VALUE then text = text:sub(1, MAX_VALUE) .. "..." end
  if text == "" or text:find("[%s=\"]") then text = '"' .. text:gsub('"', '\\"') .. '"' end
  return text
end

--- Appends `key=value` pairs, sorted by key, to the parts.
---@param parts string[]
---@param map table<string, any>
local function append_pairs(parts, map)
  local keys, values = {}, {}
  for key, value in pairs(map) do
    local name = escape(tostring(key))
    keys[#keys + 1] = name
    values[name] = value
  end
  table.sort(keys)
  for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. render(values[key]) end
end

--- Writes a record as one line.
---@param record hecate.log.Record
function ConsoleSink:write(record)
  local parts = {
    os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(record.timestamp)),
    string.upper(record.severity.name),
  }
  if record.logger then parts[#parts + 1] = "[" .. escape(record.logger) .. "]" end
  parts[#parts + 1] = (tostring(record.message):gsub("%c", " "))
  if next(record.context) ~= nil then append_pairs(parts, record.context) end
  if next(record.fields) ~= nil then append_pairs(parts, record.fields) end
  self._output(table.concat(parts, " ") .. "\n")
end

return core.finalise(ConsoleSink)
