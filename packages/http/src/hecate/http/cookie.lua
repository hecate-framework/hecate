-- Cookies (RFC 6265): parsing of the Cookie field and formatting of Set-Cookie.
global <const> require, type, error, ipairs, table, string, math, tostring

local core = require("hecate.core")
local grammar = require("hecate.http.grammar")
local imf_fixdate = require("hecate.http.date").imf_fixdate

--- A `Set-Cookie` field value under construction (RFC 6265, section 4.1).
---@class hecate.http.SetCookie
---@field name string  a token
---@field value string  cookie-octets (RFC 6265, section 4.1.1)
---@field expires? integer  epoch seconds
---@field max_age? integer  seconds; wins over `expires` in user agents (RFC 6265, section 5.3)
---@field domain? string
---@field path? string
---@field secure? boolean
---@field http_only? boolean
---@field same_site? "Strict"|"Lax"|"None"
---@overload fun(options: hecate.http.SetCookieOptions): hecate.http.SetCookie
local SetCookie = core.class("SetCookie")

---@class hecate.http.SetCookieOptions
---@field name string
---@field value string
---@field expires? integer
---@field max_age? integer
---@field domain? string
---@field path? string
---@field secure? boolean
---@field http_only? boolean
---@field same_site? "Strict"|"Lax"|"None"

local SAME_SITE <const> = { Strict = true, Lax = true, None = true }

local function refuse(message)
  error(core.ArgumentError("http.SetCookie: " .. message), 3)
end

--- Initialises a cookie definition. Everything that could break out of the field is refused here,
--- so `format` cannot produce an injected attribute.
---
--- Raises `hecate.core.ArgumentError` for an invalid name, value or attribute, or for
--- `same_site = "None"` without `secure`.
---@param options hecate.http.SetCookieOptions
function SetCookie:init(options)
  if type(options) ~= "table" then refuse("expected an options table") end
  if not grammar.is_token(options.name) then refuse("the name must be a token (RFC 6265, section 4.1.1)") end
  -- cookie-octet = %x21 / %x23-2B / %x2D-3A / %x3C-5B / %x5D-7E (section 4.1.1)
  if type(options.value) ~= "string" or string.find(options.value, '[^%w!#$%%&\'()*+%-./:<=>?@%[%]^_`{|}~]') then
    refuse("the value holds a character outside cookie-octet (RFC 6265, section 4.1.1)")
  end
  for _, attribute in ipairs({ "domain", "path" }) do
    local v = options[attribute]
    if v ~= nil and (type(v) ~= "string" or string.find(v, "[%c;]")) then refuse("invalid " .. attribute) end
  end
  for _, attribute in ipairs({ "expires", "max_age" }) do
    local v = options[attribute]
    if v ~= nil and math.type(v) ~= "integer" then refuse(attribute .. " must be an integer") end
  end
  if options.same_site ~= nil and not SAME_SITE[options.same_site] then
    refuse("same_site must be Strict, Lax or None")
  end
  if options.same_site == "None" and not options.secure then refuse("SameSite=None requires secure") end
  self.name, self.value = options.name, options.value
  self.expires, self.max_age = options.expires, options.max_age
  self.domain, self.path = options.domain, options.path
  self.secure, self.http_only, self.same_site = options.secure, options.http_only, options.same_site
end

--- Formats the field value: `name=value` then the attributes (RFC 6265, section 4.1.1).
---@return string
function SetCookie:format()
  local parts = { self.name .. "=" .. self.value }
  if self.expires then parts[#parts + 1] = "Expires=" .. imf_fixdate(self.expires) end
  if self.max_age then parts[#parts + 1] = "Max-Age=" .. self.max_age end
  if self.domain then parts[#parts + 1] = "Domain=" .. self.domain end
  if self.path then parts[#parts + 1] = "Path=" .. self.path end
  if self.secure then parts[#parts + 1] = "Secure" end
  if self.http_only then parts[#parts + 1] = "HttpOnly" end
  if self.same_site then parts[#parts + 1] = "SameSite=" .. self.same_site end
  return table.concat(parts, "; ")
end

SetCookie.__tostring = SetCookie.format

--- Cookie handling.
---@class hecate.http.Cookie
---@field SetCookie hecate.http.SetCookie
local Cookie = { SetCookie = core.finalise(SetCookie) }

--- Parses the value of a `Cookie` field (RFC 6265, section 4.2.1). Pairs are separated by `;`;
--- whitespace around them is ignored, a surrounding double quote pair is removed from a value,
--- and a malformed pair (no `=`, empty or non-token name) is skipped (section 5.4 is lenient).
--- The first occurrence of a name wins, as the user agent lists the most specific cookie first.
---@param text string
---@return table<string, string> cookies  name to value
---@return string[][] pairs  `{ name, value }` in order of occurrence, duplicates included
function Cookie.parse(text)
  local map, list = {}, {}
  if type(text) ~= "string" then return map, list end
  for item in string.gmatch(text, "[^;]+") do
    -- Split at the first `=` with `find` and indices, then trim each side: linear in the length of the pair (a lazy
    -- capture before a class of whitespace anchored at the end is quadratic).
    local equals = string.find(item, "=", 1, true)
    local name, value
    if equals ~= nil then
      name, value = grammar.trim_ows(string.sub(item, 1, equals - 1)), grammar.trim_ows(string.sub(item, equals + 1))
    end
    if name and grammar.is_token(name) then
      local inner = string.match(value, '^"(.*)"$')
      if inner then value = inner end
      list[#list + 1] = { name, value }
      if map[name] == nil then map[name] = value end
    end
  end
  return map, list
end

Cookie.imf_fixdate = imf_fixdate

return Cookie
