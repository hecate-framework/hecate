-- A sink that renders each record as one line of JSON (JSON Lines, RFC 8259 text per line).
global <const> require, type, pairs, pcall, os, math, string, next, tostring, error

local core = require("hecate.core")
local json = require("hecate.json")
local Secret = require("hecate.log.secret")
local severity_code = require("hecate.log.internal.severity").code

--- Deepest nesting walked when redacting a value; beyond it the value is replaced (it also stops cycles).
local MAX_DEPTH = 16
local TRUNCATED = "[truncated]"

--- A sink that writes one JSON object per record, followed by a newline, to a function.
---@class hecate.log.JsonLinesSink
---@overload fun(options: hecate.log.JsonLinesSinkOptions): hecate.log.JsonLinesSink
local JsonLinesSink = core.class("JsonLinesSink")

--- Options of `JsonLinesSink`.
---@class hecate.log.JsonLinesSinkOptions
---@field output fun(line: string)  receives each line, newline included; it must not suspend

--- Initialises a sink.
---
--- Raises `hecate.core.ArgumentError` if `output` is not a function.
---@param options hecate.log.JsonLinesSinkOptions
function JsonLinesSink:init(options)
  if type(options) ~= "table" or type(options.output) ~= "function" then
    error(core.ArgumentError("JsonLinesSink expects an options table with an output function"), 2)
  end
  self._output = options.output
end

--- Returns the value with every secret replaced by its redaction text; the value itself when it holds none.
---@param value any
---@param depth integer
---@return any
local function redact(value, depth)
  if type(value) ~= "table" then return value end
  if core.is_instance_of(value, Secret) then return Secret.REDACTED end
  if depth >= MAX_DEPTH then return TRUNCATED end
  local copy
  for key, item in pairs(value) do
    local redacted = redact(item, depth + 1)
    if redacted ~= item and copy == nil then
      copy = {}
      for k, v in pairs(value) do copy[k] = v end
    end
    if copy ~= nil then copy[key] = redacted end
  end
  if copy ~= nil and json.is_array(value) then json.array(copy) end
  if copy ~= nil and json.is_object(value) then json.object(copy) end
  return copy or value
end

--- RFC 3339 timestamp (the profile used by RFC 5424, section 6.2.3), UTC, with milliseconds when fractional.
---@param seconds number
---@return string
local function format_timestamp(seconds)
  local whole = math.floor(seconds)
  local text = os.date("!%Y-%m-%dT%H:%M:%S", whole)
  local milliseconds = math.floor((seconds - whole) * 1000 + 0.5)
  if milliseconds > 0 and milliseconds < 1000 then text = text .. string.format(".%03d", milliseconds) end
  return text .. "Z"
end

--- Writes a record as one line.
---@param record hecate.log.Record
function JsonLinesSink:write(record)
  local object = {
    timestamp = format_timestamp(record.timestamp),
    severity = record.severity.name,
    code = severity_code(record.severity),
    message = record.message,
    logger = record.logger,
    context = next(record.context) ~= nil and redact(record.context, 0) or nil,
    fields = next(record.fields) ~= nil and redact(record.fields, 0) or nil,
  }
  local ok, text = pcall(json.encode, object)
  if not ok then
    object.context, object.fields = nil, nil
    object.encoding_error = tostring(text)
    text = json.encode(object)
  end
  self._output(text .. "\n")
end

return core.finalise(JsonLinesSink)
