-- Path templates: the subset of RFC 6570 level 1 that routes need. A segment is a literal (RFC 3986 section 3.3,
-- `pchar`), or exactly one simple-string expansion `{name}` (RFC 6570 section 3.2.2) with optional literal text before
-- and after it (`{id}.json`, `v{major}`), or, as the last segment, the wildcard `{name...}` that stands for the rest
-- of the path. The notation `...` is the router's own (it is not RFC 6570). Several expressions in one segment are
-- refused: RFC 6570 does not define how to match them back, and `{a}-{b}` is ambiguous.
global <const> type, string, table, math, error, pairs, ipairs, tostring, require

local core = require("hecate.core")
local path = require("hecate.router.path")

--- One segment of a template.
---@class hecate.router.TemplateSegment
---@field kind "static"|"parameter"|"affixed"|"wildcard"
---@field value? string  the decoded text of a static segment
---@field name? string  the name of a parameter or of the wildcard
---@field prefix? string  the decoded literal text before the expression of an affixed segment
---@field suffix? string  the decoded literal text after the expression of an affixed segment

--- A parsed path template.
---@class hecate.router.Template
---@field text string  the template as declared
---@field segments hecate.router.TemplateSegment[]  after the trailing slash policy
---@field names string[]  the parameter names in order of appearance; the wildcard, if any, is last

--- Parsing and expansion of path templates.
---@class hecate.router.templates
local template = {}

local NAME <const> = "[%a_][%w_]*"

--- Parses a path template. Returns nil, a stable reason and a detail text for a template the router refuses: reasons
--- are `not_absolute`, `invalid_character`, `empty_segment`, `dot_segment`, `malformed_percent_encoding`,
--- `encoded_nul`, `malformed_expression`, `mixed_segment`, `duplicate_parameter` and `wildcard_not_last`.
---@param text any
---@param trailing_slash "strict"|"ignore"
---@return hecate.router.Template? template
---@return string? reason
---@return string? detail
function template.parse(text, trailing_slash)
  if type(text) ~= "string" or string.byte(text, 1) ~= 47 then
    return nil, "not_absolute", "a path template starts with a slash"
  end
  local segments, names, seen = {}, {}, {}
  local position, length = 2, #text
  while true do
    local slash = string.find(text, "/", position, true)
    local last = slash == nil
    local raw = string.sub(text, position, (slash or length + 1) - 1)
    local segment
    if string.find(raw, "[{}]") then
      local name = string.match(raw, "^{(" .. NAME .. ")}$")
      local wildcard = false
      if name == nil then
        name = string.match(raw, "^{(" .. NAME .. ")%.%.%.}$")
        wildcard = name ~= nil
      end
      local prefix, suffix
      if name == nil then
        local _, opened = string.gsub(raw, "{", "")
        local _, closed = string.gsub(raw, "}", "")
        local before, inner, after = string.match(raw, "^([^{}]*){(" .. NAME .. ")}([^{}]*)$")
        if before then
          name, prefix, suffix = inner, before, after
          for _, part in ipairs({ before, after }) do
            if string.find(part, "[^%w%-._~!$&'()*+,;=:@%%]") then
              return nil, "invalid_character", ("a literal segment holds a character that must be percent-encoded: %s"):format(raw)
            end
          end
          local decoded_before, reason = path.decode(before)
          if decoded_before == nil then return nil, reason, ("a literal segment is not valid percent-encoding: %s"):format(raw) end
          local decoded_after
          decoded_after, reason = path.decode(after)
          if decoded_after == nil then return nil, reason, ("a literal segment is not valid percent-encoding: %s"):format(raw) end
          prefix, suffix = decoded_before, decoded_after
        elseif opened == closed and opened >= 2 and not string.find(raw, "{[^}]*{") and string.find(raw, "{" .. NAME .. "%.?%.?%.?}") then
          return nil, "mixed_segment", ("a segment holds one expression with literal text around it, not several: %s"):format(raw)
        elseif opened == 1 and closed == 1 and string.find(raw, "{" .. NAME .. "%.%.%.}") then
          return nil, "mixed_segment", ("a wildcard is a whole segment, with no literal text around it: %s"):format(raw)
        else
          return nil, "malformed_expression", ("expected {name} or {name...} with a name of letters, digits and underscores: %s"):format(raw)
        end
      end
      if seen[name] then return nil, "duplicate_parameter", ("the parameter %s appears twice"):format(name) end
      seen[name] = true
      names[#names + 1] = name
      if wildcard and not last then
        return nil, "wildcard_not_last", ("the wildcard %s must be the last segment"):format(name)
      end
      if prefix ~= nil and (prefix ~= "" or suffix ~= "") then
        segment = { kind = "affixed", name = name, prefix = prefix, suffix = suffix }
      else
        segment = { kind = wildcard and "wildcard" or "parameter", name = name }
      end
    else
      if string.find(raw, "[^%w%-._~!$&'()*+,;=:@%%]") then
        return nil, "invalid_character", ("a literal segment holds a character that must be percent-encoded: %s"):format(raw)
      end
      if raw == "" and not last then return nil, "empty_segment", "an empty segment in the middle of a template" end
      local decoded, reason = path.decode(raw)
      if decoded == nil then return nil, reason, ("a literal segment is not valid percent-encoding: %s"):format(raw) end
      if decoded == "." or decoded == ".." then
        return nil, "dot_segment", "a dot segment can never match: the router resolves them in the request path"
      end
      segment = { kind = "static", value = decoded }
    end
    segments[#segments + 1] = segment
    if last then break end
    position = slash + 1
  end
  local final = segments[#segments]
  if trailing_slash == "ignore" and final.kind == "static" and final.value == "" then segments[#segments] = nil end
  return { text = text, segments = segments, names = names }
end

local function refuse(message) error(core.ArgumentError("router.url_for: " .. message), 4) end

--- A reverse-routing value is a string or an integer that stays one segment after matching.
local function segment_text(name, value, inside)
  local kind = math.type(value)
  if kind == "integer" then return tostring(value) end
  if type(value) ~= "string" then refuse(("parameter %s must be a string or an integer"):format(name)) end
  if value == "" or (not inside and (value == "." or value == "..")) or string.find(value, "\0", 1, true) then
    refuse(("parameter %s is empty, a dot segment or holds a NUL byte, which no request path can carry"):format(name))
  end
  return value
end

--- Builds the path of `parsed` from `parameters`: every value is percent-encoded (RFC 6570 section 3.2.2, level 1
--- expansion keeps only the unreserved characters). The value of a wildcard is split at its slashes and each part is
--- encoded, so it matches the wildcard again.
---
--- Raises `hecate.core.ArgumentError` for a missing or unknown parameter and for a value that matching could not read
--- back (empty, `.`, `..`, a NUL byte, an empty part in a wildcard value).
---@param parsed hecate.router.Template
---@param parameters? table<string, string|integer>
---@return string path
function template.expand(parsed, parameters)
  parameters = parameters or {}
  local known = {}
  for _, name in ipairs(parsed.names) do known[name] = true end
  for name in pairs(parameters) do
    if not known[name] then refuse(("unknown parameter %s"):format(tostring(name))) end
  end
  local out = {}
  for _, segment in ipairs(parsed.segments) do
    if segment.kind == "static" then
      out[#out + 1] = path.encode(segment.value, true)
    else
      local value = parameters[segment.name]
      if value == nil then refuse(("missing parameter %s"):format(segment.name)) end
      if segment.kind == "parameter" then
        out[#out + 1] = path.encode(segment_text(segment.name, value))
      elseif segment.kind == "affixed" then
        local text = segment_text(segment.name, value, true)
        if segment.prefix .. text .. segment.suffix == "." or segment.prefix .. text .. segment.suffix == ".." then
          refuse(("parameter %s would make a dot segment"):format(segment.name))
        end
        out[#out + 1] = path.encode(segment.prefix, true) .. path.encode(text) .. path.encode(segment.suffix, true)
      else
        if type(value) ~= "string" then refuse(("parameter %s must be a string"):format(segment.name)) end
        ---@cast value string
        local parts, start = {}, 1
        while true do
          local slash = string.find(value, "/", start, true)
          parts[#parts + 1] = path.encode(segment_text(segment.name, string.sub(value, start, (slash or #value + 1) - 1)))
          if slash == nil then break end
          start = slash + 1
        end
        out[#out + 1] = table.concat(parts, "/")
      end
    end
  end
  return "/" .. table.concat(out, "/")
end

return template
