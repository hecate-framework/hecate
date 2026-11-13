-- Serialisation of HTTP/1.1 response messages (RFC 9112, sections 4, 5 and 7.1; RFC 9110, section 5.6.7).
global <const> require, string, table, type

local Status = require("hecate.http.status")
local grammar = require("hecate.http.grammar")
local date = require("hecate.http.date")

--- Pure helpers that turn a response into bytes.
---@class hecate.http.wire
local wire = {}

--- Formats an instant as an HTTP-date (RFC 9110, section 5.6.7: IMF-fixdate), by arithmetic: no `os.date`, so no locale and
--- no time zone database. The same function as `Set-Cookie` uses (`hecate.http.date`).
---@param time integer  seconds since the epoch
---@return string
function wire.http_date(time) return date.imf_fixdate(time) end

--- A reason phrase that is safe to emit: no control character (RFC 9112, section 4 allows HTAB, SP, VCHAR and obs-text); anything else
--- replaces the phrase by the registered one for the status, or by the empty phrase.
---@param reason string?
---@param status integer
---@return string
function wire.reason(reason, status)
  if type(reason) == "string" and not string.find(reason, "[%c\127]") then return reason end
  return Status.reason(status) or ""
end

--- The status line and the fields of a response, with the empty line that ends them. `fields` is iterated with
--- `lines()`: every line is emitted in order.
---@param status integer
---@param reason string
---@param fields hecate.http.Fields
---@return string
function wire.head(status, reason, fields)
  local out = { "HTTP/1.1 ", status, " ", wire.reason(reason, status), "\r\n" }
  for name, value in fields:lines() do
    out[#out + 1] = name
    out[#out + 1] = ": "
    out[#out + 1] = value
    out[#out + 1] = "\r\n"
  end
  out[#out + 1] = "\r\n"
  return table.concat(out)
end

--- One chunk of the chunked transfer coding (RFC 9112, section 7.1). An empty `data` yields the empty string: a
--- zero-size chunk would end the content.
---@param data string
---@return string
function wire.chunk(data)
  if data == "" then return "" end
  return string.format("%x\r\n", #data) .. data .. "\r\n"
end

--- The last chunk and the empty trailer section of the chunked coding.
wire.LAST_CHUNK = "0\r\n\r\n"

--- Reports whether a `Connection` field value lists `option` (RFC 9110, section 7.6.1), case-insensitively.
---@param value string?
---@param option string
---@return boolean
function wire.has_connection_option(value, option)
  if value == nil then return false end
  for item in string.gmatch(value, "[^,]+") do
    if string.lower(grammar.trim_ows(item)) == option then return true end
  end
  return false
end

return wire
