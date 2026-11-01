-- Case-insensitive, multi-valued, order-preserving header fields (RFC 9110, section 5).
global <const> require, type, error, ipairs, pairs, table, string, tostring

local core = require("hecate.core")
local grammar = require("hecate.http.grammar")

--- The fields of a message. Field names compare case-insensitively (RFC 9110, section 5.1); a name
--- may occur several times and the order of occurrence is preserved (section 5.3). The name is
--- stored as first written, so a message is emitted as it was received.
---@class hecate.http.Fields
---@overload fun(initial?: table<string, string|string[]>|string[][]): hecate.http.Fields
local Fields = core.class("Fields")

local function invalid(what, value, rule)
  error(core.ArgumentError(("http.Fields: invalid %s %q: %s"):format(what, tostring(value), rule)), 3)
end

local function check(name, value)
  if not grammar.is_token(name) then invalid("field name", name, "expected a token (RFC 9110, section 5.6.2)") end
  if not grammar.is_field_value(value) then
    invalid("field value", value, "expected a string without CR, LF or NUL (RFC 9110, section 5.5)")
  end
end

--- Initialises fields, optionally from a list of `{ name, value }` pairs (order kept) or from a
--- map of name to value or list of values (order unspecified, for convenience).
---
--- Raises `hecate.core.ArgumentError` for an invalid name or value.
---@param initial? table<string, string|string[]>|string[][]
function Fields:init(initial)
  self._entries = {}  -- list of { name = original name, key = lowercase, value = string }
  if initial == nil then return end
  for k, v in pairs(initial) do
    if type(k) == "number" then
      self:add(v[1], v[2])
    elseif type(v) == "table" then
      for _, item in ipairs(v) do self:add(k, item) end
    else
      self:add(k, v)
    end
  end
end

--- Appends a field line; earlier lines of the same name stay.
---
--- Raises `hecate.core.ArgumentError` for an invalid name or value.
---@param name string
---@param value string  leading and trailing whitespace is trimmed (RFC 9110, section 5.5)
---@return hecate.http.Fields self
function Fields:add(name, value)
  check(name, value)
  value = string.match(value, "^[ \t]*(.-)[ \t]*$")
  local entries = self._entries
  entries[#entries + 1] = { name = name, key = string.lower(name), value = value }
  return self
end

--- Replaces every line of `name` by one line, at the position of the first replaced line, or
--- appends it when absent.
---@param name string
---@param value string
---@return hecate.http.Fields self
function Fields:set(name, value)
  check(name, value)
  value = string.match(value, "^[ \t]*(.-)[ \t]*$")
  local key, entries, kept, placed = string.lower(name), self._entries, {}, false
  for _, entry in ipairs(entries) do
    if entry.key ~= key then
      kept[#kept + 1] = entry
    elseif not placed then
      kept[#kept + 1] = { name = name, key = key, value = value }
      placed = true
    end
  end
  if not placed then kept[#kept + 1] = { name = name, key = key, value = value } end
  self._entries = kept
  return self
end

--- Returns the value of the first line of `name`, or nil.
---@param name string
---@return string? value
function Fields:get(name)
  local key = string.lower(name)
  for _, entry in ipairs(self._entries) do
    if entry.key == key then return entry.value end
  end
  return nil
end

--- Returns the values of every line of `name`, in order (empty list when absent).
---@param name string
---@return string[] values
function Fields:get_all(name)
  local key, values = string.lower(name), {}
  for _, entry in ipairs(self._entries) do
    if entry.key == key then values[#values + 1] = entry.value end
  end
  return values
end

--- Returns the lines of `name` combined into one value, joined by `, ` (RFC 9110, section 5.3),
--- or nil when absent. `Set-Cookie` cannot be combined and is refused: use `get_all`.
---
--- Raises `hecate.core.ArgumentError` for `Set-Cookie`.
---@param name string
---@return string? value
function Fields:combined(name)
  if string.lower(name) == "set-cookie" then
    error(core.ArgumentError("http.Fields: Set-Cookie cannot be combined (RFC 9110, section 5.3); use get_all"), 2)
  end
  local values = self:get_all(name)
  if #values == 0 then return nil end
  return table.concat(values, ", ")
end

--- Reports whether at least one line of `name` exists.
---@param name string
---@return boolean
function Fields:has(name)
  return self:get(name) ~= nil
end

--- Removes every line of `name`; returns how many were removed.
---@param name string
---@return integer removed
function Fields:remove(name)
  local key, kept = string.lower(name), {}
  for _, entry in ipairs(self._entries) do
    if entry.key ~= key then kept[#kept + 1] = entry end
  end
  local removed = #self._entries - #kept
  self._entries = kept
  return removed
end

--- Returns the number of field lines.
---@return integer
function Fields:count()
  return #self._entries
end

--- Iterates the lines in order of occurrence, yielding the name as first written and the value.
---@return fun(): string?, string?
function Fields:lines()
  local i = 0
  return function()
    i = i + 1
    local entry = self._entries[i]
    if entry then return entry.name, entry.value end
  end
end

--- Returns an independent copy.
---@return hecate.http.Fields
function Fields:copy()
  local copy = Fields()
  for _, entry in ipairs(self._entries) do
    copy._entries[#copy._entries + 1] = { name = entry.name, key = entry.key, value = entry.value }
  end
  return copy
end

return core.finalise(Fields)
