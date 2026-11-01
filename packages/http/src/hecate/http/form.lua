-- application/x-www-form-urlencoded (WHATWG URL Standard, section 5.1; percent-encoding of RFC 3986 section 2.1).
global <const> require, type, error, string, table, math, ipairs, pairs, tostring, tonumber, utf8

local core = require("hecate.core")

--- The content of a form could not be accepted: an unsupported media type, malformed or too large. `context.kind` is a
--- stable identifier (`unsupported_media_type`, `bad_percent_encoding`, `invalid_utf8`, `nul_in_value`, `too_many_pairs`,
--- `too_large`, `bad_boundary`, `bad_part_header`, `missing_name`, `too_many_parts`, `part_header_too_large`,
--- `total_too_large`, `truncated`, `malformed`) and `context.status` the status code to answer with (400, 413 or 415).
--- The message never holds input bytes.
---@class hecate.http.FormError : hecate.core.ProtocolError
---@field context { kind: string, status: integer }
local FormError = core.error_class("FormError", "hecate.http.FormError", core.ProtocolError)

local STATUS_OF_KIND <const> = {
  unsupported_media_type = 415,
  too_many_pairs = 413, too_large = 413, too_many_parts = 413, part_header_too_large = 413, total_too_large = 413,
}

--- Builds a `FormError` of `kind` (its status follows from the kind, 400 unless listed above).
---@param kind string
---@param message string
---@return hecate.http.FormError
local function failure(kind, message)
  return FormError({ message = "http.form: " .. message, context = { kind = kind, status = STATUS_OF_KIND[kind] or 400 } })
end

--- An ordered multi-map of form pairs: names repeat, order is kept.
---@class hecate.http.Form
---@overload fun(pairs?: string[][]): hecate.http.Form
local Form = core.class("Form")

--- Creates a form from a list of `{ name, value }` pairs.
---@param list? string[][]
function Form:init(list)
  self._pairs = {}
  for _, pair in ipairs(list or {}) do
    if type(pair[1]) ~= "string" or type(pair[2]) ~= "string" then
      error(core.ArgumentError("http.Form: a pair is { name, value } with two strings"), 3)
    end
    self._pairs[#self._pairs + 1] = { pair[1], pair[2] }
  end
end

--- Returns the first value of `name`, or nil.
---@param name string
---@return string?
function Form:get(name)
  for _, pair in ipairs(self._pairs) do
    if pair[1] == name then return pair[2] end
  end
  return nil
end

--- Returns every value of `name`, in order.
---@param name string
---@return string[]
function Form:get_all(name)
  local values = {}
  for _, pair in ipairs(self._pairs) do
    if pair[1] == name then values[#values + 1] = pair[2] end
  end
  return values
end

--- Returns the number of pairs.
---@return integer
function Form:count() return #self._pairs end

--- Iterates the pairs in order, yielding name and value.
---@return fun(): string?, string?
function Form:pairs()
  local i = 0
  return function()
    i = i + 1
    local pair = self._pairs[i]
    if pair then return pair[1], pair[2] end
  end
end

Form = core.finalise(Form)

--- Form content: urlencoded parsing and encoding, and the error of every form format.
---@class hecate.http.form
---@field Form hecate.http.Form
---@field FormError hecate.http.FormError
local form = { Form = Form, FormError = FormError, failure = failure }

--- Limits of the urlencoded parser, with their defaults.
---@class hecate.http.form.Limits
---@field max_pairs? integer  pairs (default 1000; over it: 413)
---@field max_size? integer  bytes of the text (default 1048576; over it: 413)

--- Defaults of the limits of the urlencoded parser.
form.DEFAULTS = { max_pairs = 1000, max_size = 1048576 }

---@param limits any
---@return integer max_pairs
---@return integer max_size
local function check_limits(limits)
  if limits ~= nil and type(limits) ~= "table" then error(core.ArgumentError("http.form: limits must be a table"), 3) end
  limits = limits or {}
  for key, value in pairs(limits) do
    if (key ~= "max_pairs" and key ~= "max_size") or math.type(value) ~= "integer" or value < 0 then
      error(core.ArgumentError("http.form: invalid limit " .. tostring(key) .. " (max_pairs and max_size, non-negative integers)"), 3)
    end
  end
  return limits.max_pairs or form.DEFAULTS.max_pairs, limits.max_size or form.DEFAULTS.max_size
end

--- Decodes one component: `+` is a space, `%XX` a byte. A `%` not followed by two hexadecimal digits is refused
--- (the WHATWG parser keeps it literally; a server that guesses is a request-smuggling aid), and so are a result that
--- is not valid UTF-8 and a NUL byte.
local function decode(text)
  -- A plus is a space, an encoded plus (%2B) stays a plus: the plus signs are replaced BEFORE the percent sequences.
  text = string.gsub(text, "%+", " ")
  if string.find(text, "%%") then
    if string.find(text, "%%%x?[^%x]") or string.find(text, "%%%x?$") then
      error(failure("bad_percent_encoding", "malformed percent-encoding in a form"), 0)
    end
    text = string.gsub(text, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  end
  if string.find(text, "%z") then error(failure("nul_in_value", "a NUL byte in a form value"), 0) end
  if not utf8.len(text) then error(failure("invalid_utf8", "a form value is not valid UTF-8"), 0) end
  return text
end

--- Parses `application/x-www-form-urlencoded` text into a `Form`. Pairs are separated by `&` (empty ones are skipped),
--- name and value by the first `=` (no `=`: an empty value); names repeat and keep their order.
---
--- Raises `hecate.http.FormError` for text beyond `limits.max_size` or more than `limits.max_pairs` pairs (413), a
--- malformed percent sequence, invalid UTF-8 or a NUL byte (400). Raises `hecate.core.ArgumentError` for bad arguments.
---@param text string
---@param limits? hecate.http.form.Limits
---@return hecate.http.Form
function form.parse_urlencoded(text, limits)
  if type(text) ~= "string" then error(core.ArgumentError("http.form.parse_urlencoded expects a string"), 2) end
  local max_pairs, max_size = check_limits(limits)
  if #text > max_size then error(failure("too_large", "the form exceeds its size limit"), 2) end
  local result = Form()
  for segment in string.gmatch(text, "[^&]+") do
    if #result._pairs >= max_pairs then error(failure("too_many_pairs", "the form has too many pairs"), 2) end
    local name, value = string.match(segment, "^([^=]*)=?(.*)$")
    result._pairs[#result._pairs + 1] = { decode(name), decode(value) }
  end
  return result
end

local function encode(text)
  return (string.gsub(string.gsub(text, "[^%w%*%-%._ ]", function(c) return string.format("%%%02X", string.byte(c)) end), " ", "+"))
end

--- Encodes pairs as `application/x-www-form-urlencoded`: a list of `{ name, value }` or a `Form`. Bytes outside
--- `A-Z a-z 0-9 * - . _` are percent-encoded, a space is `+`.
---
--- Raises `hecate.core.ArgumentError` for anything but a list of pairs of strings.
---@param pairs_ string[][]|hecate.http.Form
---@return string
function form.encode_urlencoded(pairs_)
  local list = pairs_
  if type(pairs_) == "table" and core.is_instance_of(pairs_, Form) then list = pairs_._pairs end
  if type(list) ~= "table" then error(core.ArgumentError("http.form.encode_urlencoded expects a list of { name, value } pairs"), 2) end
  local out = {}
  for _, pair in ipairs(list) do
    if type(pair) ~= "table" or type(pair[1]) ~= "string" or type(pair[2]) ~= "string" then
      error(core.ArgumentError("http.form.encode_urlencoded: a pair is { name, value } with two strings"), 2)
    end
    out[#out + 1] = encode(pair[1]) .. "=" .. encode(pair[2])
  end
  return table.concat(out, "&")
end

return form
