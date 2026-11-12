-- The checks of the `format` option of `string` (JSON Schema 2020-12 section 7.3).
-- Internal to `hecate.schema`: not public API. Only `internal/base_types.lua` requires it.
global <const> tonumber, ipairs

--- Checks of the `format` option of `string` (JSON Schema 2020-12 section 7.3). Conservative subsets: `uuid` (RFC 9562 text
--- form), `date` and `date-time` (RFC 3339), `email` (one `@`, non-empty local part and dotted domain, no whitespace), `ipv4` (dotted quad, RFC 2673 section 3.2, no leading zeros), `uri` (RFC 3986 URI with a scheme: only unreserved, reserved and percent-encoded characters).
local function days_in_month(year, month)
  if month == 2 then return (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 29 or 28 end
  return (month == 4 or month == 6 or month == 9 or month == 11) and 30 or 31
end

local function is_date(text)
  local y, m, d = text:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return false end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  return m >= 1 and m <= 12 and d >= 1 and d <= days_in_month(y, m)
end

local FORMATS = {
  uuid = function(text)
    return text:find("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
  end,
  date = is_date,
  ["date-time"] = function(text)
    local date, time = text:match("^(%d%d%d%d%-%d%d%-%d%d)[Tt](.+)$")
    if not date or not is_date(date) then return false end
    local h, mi, s, rest = time:match("^(%d%d):(%d%d):(%d%d)(.*)$")
    if not h or tonumber(h) > 23 or tonumber(mi) > 59 or tonumber(s) > 60 then return false end
    rest = rest:gsub("^%.%d+", "")
    if rest == "Z" or rest == "z" then return true end
    local oh, om = rest:match("^[+-](%d%d):(%d%d)$")
    return oh ~= nil and tonumber(oh) <= 23 and tonumber(om) <= 59
  end,
  ipv4 = function(text)
    local a, b, c, d = text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    for _, part in ipairs({ a, b, c, d }) do
      if #part > 3 or (#part > 1 and part:sub(1, 1) == "0") or tonumber(part) > 255 then return false end
    end
    return true
  end,
  uri = function(text)
    if not text:find("^[A-Za-z][A-Za-z0-9+.-]*:") then return false end
    if text:find("[^A-Za-z0-9%-._~:/?#%[%]@!$&'()*+,;=%%]") then return false end
    return not text:gsub("%%%x%x", ""):find("%%")
  end,
  email = function(text)
    -- No whitespace or control character (bytes below 32 and 127), at most 254 bytes (RFC 5321 section 4.5.3.1.3).
    if #text > 254 or text:find("[%s%c]") then return false end
    local local_part, domain = text:match("^([^@]+)@([^@]+)$")
    return local_part ~= nil and domain:find("^[^.]+%.[^.]+") ~= nil and not domain:find("%.%.")
      and not domain:find("^%.") and not domain:find("%.$")
  end,
}

---@class hecate.schema.internal.formats
return FORMATS
