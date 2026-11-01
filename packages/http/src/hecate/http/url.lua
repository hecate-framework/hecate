-- URLs of the http and https schemes as the client needs them (RFC 3986 section 3, RFC 9110 section 4.2).
-- Strict on purpose: no userinfo (RFC 9110 section 4.2.4 deprecates it), no control characters, no whitespace, no
-- non-ASCII bytes (percent-encode them), no scheme other than http and https.
global <const> require, type, string, math, table

local core = require("hecate.core")

--- A parsed absolute URL. `target` is the origin-form request target (RFC 9112 section 3.2.1).
---@class hecate.http.Url
---@field scheme "http"|"https"
---@field host string  lowercase; an IPv6 literal without its brackets
---@field port integer  the explicit port or the default of the scheme
---@field path string  at least "/"
---@field query string?  without `?`
---@field target string  `path` and `?query`
---@field authority string  the `Host` field value: default ports are omitted, IPv6 literals bracketed
---@field origin string  `scheme://authority`, the key of a connection pool

--- Strict parsing and resolution of http and https URLs.
---@class hecate.http.url
local url = {}

local DEFAULT_PORT <const> = { http = 80, https = 443 }

--- Parses an absolute http or https URL. Returns nil and a reason for anything else; the fragment is dropped.
---@param text any
---@return hecate.http.Url? parsed
---@return string? reason
function url.parse(text)
  if type(text) ~= "string" then return nil, "the URL must be a string" end
  if string.find(text, "[%c%s\127-\255]") then return nil, "the URL holds whitespace, control or non-ASCII characters (percent-encode them)" end
  local scheme, rest = string.match(text, "^(%a[%w+.-]*)://(.*)$")
  if scheme == nil then return nil, "the URL must be absolute: scheme://host/path" end
  scheme = string.lower(scheme)
  if scheme ~= "http" and scheme ~= "https" then return nil, "the scheme must be http or https" end
  rest = string.gsub(rest, "#.*$", "")
  local authority, tail = string.match(rest, "^([^/?]*)(.*)$")
  if string.find(authority, "@", 1, true) then return nil, "userinfo in a URL is refused (RFC 9110 section 4.2.4)" end
  local host, port_text
  local bracketed = string.sub(authority, 1, 1) == "["
  if string.sub(authority, 1, 1) == "[" then
    local literal, after = string.match(authority, "^%[([%x:%.]+)%](.*)$")
    if literal == nil or not string.find(literal, ":", 1, true) then return nil, "malformed IPv6 literal" end
    host = literal
    if after ~= "" then
      port_text = string.match(after, "^:(%d*)$")
      if port_text == nil then return nil, "malformed port" end
    end
  else
    local name, port = string.match(authority, "^([^:]*):?(.*)$")
    host = name
    if string.find(authority, ":", 1, true) then
      port_text = port
      if string.find(port, "^%d*$") == nil then return nil, "malformed port" end
    end
  end
  if host == "" or (not bracketed and string.find(host, "[%[%]:]")) then return nil, "the URL has no valid host" end
  host = string.lower(host)
  local port = DEFAULT_PORT[scheme]
  if port_text ~= nil and port_text ~= "" then
    local number = math.tointeger(port_text)
    if number == nil or number < 1 or number > 65535 then return nil, "the port must be from 1 to 65535" end
    port = number
  end
  local path, query = string.match(tail, "^([^?]*)%??(.*)$")
  if path == "" then path = "/" end
  if string.sub(path, 1, 1) ~= "/" then return nil, "malformed path" end
  if string.find(tail, "?", 1, true) == nil then query = nil end
  local shown = string.find(host, ":", 1, true) and ("[" .. host .. "]") or host
  local authority_text = port == DEFAULT_PORT[scheme] and shown or (shown .. ":" .. port)
  return {
    scheme = scheme, host = host, port = port, path = path, query = query,
    target = query ~= nil and (path .. "?" .. query) or path,
    authority = authority_text, origin = scheme .. "://" .. authority_text,
  }
end

--- Resolves a `Location` value against the URL of the request (RFC 3986 section 5, enough for redirects: absolute URLs,
--- network-path (`//host/x`), absolute paths, relative paths with dot segments, and query-only references).
--- Returns the absolute URL text, or nil and a reason.
---@param base hecate.http.Url
---@param reference string
---@return string? absolute
---@return string? reason
function url.resolve(base, reference)
  if type(reference) ~= "string" or reference == "" then return nil, "empty Location" end
  if string.find(reference, "^%a[%w+.-]*:") then return reference end
  local prefix = base.scheme .. "://" .. base.authority
  if string.sub(reference, 1, 2) == "//" then return base.scheme .. ":" .. reference end
  reference = string.gsub(reference, "#.*$", "")
  if string.sub(reference, 1, 1) == "?" then return prefix .. base.path .. reference end
  if string.sub(reference, 1, 1) == "/" then return prefix .. url.normalise_path(reference) end
  local directory = string.match(base.path, "^(.*/)") or "/"
  return prefix .. url.normalise_path(directory .. reference)
end

--- Removes the dot segments of a path (RFC 3986 section 5.2.4); a query stays as it is.
---@param path string
---@return string
function url.normalise_path(path)
  local only, query = string.match(path, "^([^?]*)(.*)$")
  local out = {}
  for segment in string.gmatch(only, "[^/]*") do
    if segment == ".." then
      if #out > 1 then out[#out] = nil end
    elseif segment ~= "." then
      out[#out + 1] = segment
    end
  end
  local joined = table.concat(out, "/")
  if string.match(only, "/%.%.?$") then joined = joined .. "/" end
  if string.sub(joined, 1, 1) ~= "/" then joined = "/" .. joined end
  return joined .. query
end

return url
