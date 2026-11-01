-- HTTP-date (RFC 9110, section 5.6.7), shared by `Set-Cookie` (RFC 6265) and the `Date` field of the server.
global <const> string

local DAYS <const> = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHS <const> = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

--- Formats epoch seconds as an IMF-fixdate (RFC 9110, section 5.6.7), independent of the locale.
---@param seconds integer
---@return string
local function imf_fixdate(seconds)
  local days, rem = seconds // 86400, seconds % 86400
  -- Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
  local z = days + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local day = doy - (153 * mp + 2) // 5 + 1
  local month = mp < 10 and mp + 3 or mp - 9
  local year = yoe + era * 400 + (month <= 2 and 1 or 0)
  return string.format("%s, %02d %s %04d %02d:%02d:%02d GMT", DAYS[(days + 4) % 7 + 1], day, MONTHS[month], year,
    rem // 3600, rem % 3600 // 60, rem % 60)
end

--- HTTP-dates, computed by arithmetic.
---@class hecate.http.date
local date = { imf_fixdate = imf_fixdate }

return date
