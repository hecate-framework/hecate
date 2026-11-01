-- Media types (RFC 9110, section 8.3.1).
global <const> require, type, error, pairs, ipairs, table, string, tostring

local core = require("hecate.core")
local grammar = require("hecate.http.grammar")

--- A media type: `type/subtype` and parameters, for example `application/json; charset=utf-8`.
--- Type, subtype and parameter names compare case-insensitively and are stored in lowercase;
--- parameter values keep their case (RFC 9110, section 8.3.1).
---@class hecate.http.MediaType
---@field type string  lowercase, for example "application"
---@field subtype string  lowercase, for example "json"
---@field parameters table<string, string>  lowercase name to value
---@field order string[]  parameter names in order of occurrence
---@overload fun(type: string, subtype: string, parameters?: table<string, string>): hecate.http.MediaType
local MediaType = core.class("MediaType")

--- Initialises a media type.
---
--- Raises `hecate.core.ArgumentError` if a part is not a token.
---@param type_ string
---@param subtype string
---@param parameters? table<string, string>  parameters; order of a map is sorted by name
function MediaType:init(type_, subtype, parameters)
  if not grammar.is_token(type_) or not grammar.is_token(subtype) then
    error(core.ArgumentError("http.MediaType: type and subtype must be tokens"), 3)
  end
  self.type, self.subtype = string.lower(type_), string.lower(subtype)
  self.parameters, self.order = {}, {}
  local names = {}
  for name in pairs(parameters or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do self:set_parameter(name, parameters[name]) end
end

--- Sets a parameter (replacing an earlier one of the same name).
---
--- Raises `hecate.core.ArgumentError` if the name is not a token or the value holds CR, LF or NUL.
---@param name string
---@param value string
function MediaType:set_parameter(name, value)
  if not grammar.is_token(name) or not grammar.is_field_value(value) then
    error(core.ArgumentError("http.MediaType: invalid parameter " .. tostring(name)), 2)
  end
  name = string.lower(name)
  if self.parameters[name] == nil then self.order[#self.order + 1] = name end
  self.parameters[name] = value
end

--- Returns `type/subtype` without parameters.
---@return string
function MediaType:essence()
  return self.type .. "/" .. self.subtype
end

--- Returns the structured syntax suffix of the subtype (`json` for `application/problem+json`), or nil.
---@return string?
function MediaType:suffix()
  return string.match(self.subtype, "%+([^+]+)$")
end

--- Reports whether this media type is `other` (a string such as "application/json" or a
--- range such as "application/*", "*/*"), ignoring parameters.
---@param range string
---@return boolean
function MediaType:matches(range)
  range = string.lower(range)
  if range == "*/*" then return true end
  if range == self.type .. "/*" then return true end
  return range == self:essence()
end

--- Formats as a field value; a parameter value that is not a token is written as a quoted-string.
---@return string
function MediaType:format()
  local parts = { self:essence() }
  for _, name in ipairs(self.order) do
    local value = self.parameters[name]
    if not grammar.is_token(value) then
      value = '"' .. string.gsub(value, '(["\\])', "\\%1") .. '"'
    end
    parts[#parts + 1] = name .. "=" .. value
  end
  return table.concat(parts, "; ")
end

MediaType.__tostring = MediaType.format

--- Parses a `Content-Type` style value. Malformed input yields nil and a reason, never an error.
---@param text string
---@return hecate.http.MediaType? media_type
---@return string? reason
function MediaType.parse(text)
  if type(text) ~= "string" then return nil, "not a string" end
  local type_, subtype, rest = string.match(text, "^[ \t]*([^/ \t;]+)/([^/ \t;]+)(.-)$")
  if not type_ or not grammar.is_token(type_) or not grammar.is_token(subtype) then
    return nil, "expected type/subtype"
  end
  local media = MediaType(type_, subtype)
  local pos = 1
  while pos <= #rest do
    local after = string.match(rest, "^[ \t]*;[ \t]*()", pos)
    if not after then
      if string.match(rest, "^[ \t]*$", pos) then break end
      return nil, "expected ';' before a parameter"
    end
    pos = after
    if pos > #rest then break end  -- a trailing ';' is tolerated
    local name, value_start = string.match(rest, "^([^=;%s]+)=()", pos)
    if not name or not grammar.is_token(name) then return nil, "malformed parameter" end
    pos = value_start
    local value
    if string.sub(rest, pos, pos) == '"' then
      local out, i = {}, pos + 1
      while true do
        local c = string.sub(rest, i, i)
        if c == "" then return nil, "unterminated quoted-string" end
        if c == "\\" then
          i = i + 1
          c = string.sub(rest, i, i)
          if c == "" then return nil, "unterminated quoted-string" end
        elseif c == '"' then break end
        out[#out + 1] = c
        i = i + 1
      end
      value, pos = table.concat(out), i + 1
    else
      value, pos = string.match(rest, "^([^;%s]*)()", pos)
      if not grammar.is_token(value) then return nil, "malformed parameter value" end
    end
    local lower = string.lower(name)
    if media.parameters[lower] == nil then media:set_parameter(lower, value) end  -- first wins
  end
  return media
end

return core.finalise(MediaType)
