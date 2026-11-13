-- The request path as the router reads it. `http.Request.path` is raw (OQ-75): this module percent-decodes each
-- segment on its own (RFC 3986 section 2.1, so `%2F` is data and not a separator) and resolves dot segments
-- (RFC 3986 section 5.2.4).
global <const> type, string, tonumber, require, error

local core = require("hecate.core")

--- Splitting, decoding and encoding of URI paths.
---@class hecate.router.paths
local path = {}

local malformed = false

-- The `gsub` callback of `decode`: a `%` must be followed by two hexadecimal digits (RFC 3986 section 2.1).
local function decode_triplet(digits)
  if string.find(digits, "^%x%x$") then return string.char(tonumber(digits, 16)) end
  malformed = true
  return nil
end

--- Percent-decodes `text` once (RFC 3986 section 2.1). Returns nil and a reason (`malformed_percent_encoding`,
--- `encoded_nul`) when a `%` is not followed by two hexadecimal digits or when the result holds a NUL byte.
---@param text string
---@return string? decoded
---@return string? reason
function path.decode(text)
  if not string.find(text, "%", 1, true) then
    if string.find(text, "\0", 1, true) then return nil, "encoded_nul" end
    return text
  end
  malformed = false
  local decoded = string.gsub(text, "%%(.?.?)", decode_triplet)
  if malformed then return nil, "malformed_percent_encoding" end
  if string.find(decoded, "\0", 1, true) then return nil, "encoded_nul" end
  return decoded
end

--- Percent-encodes `text`: every byte except the unreserved characters (RFC 3986 section 2.3) becomes `%XX`. With
--- `keep_delimiters`, the sub-delimiters, `:` and `@` stay as they are, which is the rest of a path segment
--- (RFC 3986 section 3.3, `pchar`).
---@param text string
---@param keep_delimiters? boolean
---@return string
function path.encode(text, keep_delimiters)
  local pattern = keep_delimiters and "[^%w%-._~!$&'()*+,;=:@]" or "[^%w%-._~]"
  local encoded = string.gsub(text, pattern, function(byte) return string.format("%%%02X", string.byte(byte)) end)
  return encoded
end

--- Splits a raw path into decoded segments. Each segment is decoded on its own; a segment that is `.` or `..` after
--- decoding is a dot segment (RFC 3986 section 6.2.2.2: `%2E` is `.`) and is resolved before matching, so `..` never
--- climbs above the root. The path `/` gives no segment under the `ignore` policy and one empty segment under `strict`,
--- like every path with a trailing slash (`/a/` gives `a` and an empty segment); `ignore` drops that one segment.
---
--- Returns nil and a reason (`not_absolute`, `malformed_percent_encoding`, `encoded_nul`) for a path the router
--- refuses. Raises `hecate.core.ArgumentError` for a `trailing_slash` policy other than `"strict"` and `"ignore"`.
---@param raw string  the path component of the request target, raw
---@param trailing_slash? "strict"|"ignore"  default `"ignore"`, as for `Router`
---@return string[]? segments
---@return string? reason
function path.split(raw, trailing_slash)
  if trailing_slash == nil then
    trailing_slash = "ignore"
  elseif trailing_slash ~= "ignore" and trailing_slash ~= "strict" then
    error(core.ArgumentError("router.path.split: trailing_slash must be \"strict\" or \"ignore\""), 2)
  end
  if type(raw) ~= "string" or string.byte(raw, 1) ~= 47 then return nil, "not_absolute" end
  local out, count = {}, 0
  local position, length = 2, #raw
  local trailing = false -- the last raw segment was a dot segment: the result ends in a slash (RFC 3986 section 5.2.4)
  while true do
    local slash = string.find(raw, "/", position, true)
    local segment = string.sub(raw, position, (slash or length + 1) - 1)
    local decoded, reason = path.decode(segment)
    if decoded == nil then return nil, reason end
    local last = slash == nil
    if decoded == "." then
      trailing = last
    elseif decoded == ".." then
      if count > 0 then out[count] = nil; count = count - 1 end
      trailing = last
    else
      count = count + 1
      out[count] = decoded
      trailing = false
    end
    if last then break end
    position = slash + 1
  end
  if trailing then out[count + 1] = "" end
  if trailing_slash == "ignore" and out[#out] == "" then out[#out] = nil end
  return out
end

return path
