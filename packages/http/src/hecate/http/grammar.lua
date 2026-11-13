-- Character classes of the RFC 9110 grammar shared by the message model.
global <const> string, type

--- Lexical helpers of RFC 9110, section 5.6.2 (tokens) and RFC 5234 character classes.
---@class hecate.http.grammar
local grammar = {}

--- Lua pattern matching a whole token (RFC 9110, section 5.6.2: 1*tchar).
grammar.TOKEN = "^[!#$%%&'*+%-.^_`|~%w]+$"

--- Reports whether `text` is a non-empty token.
---@param text any
---@return boolean
function grammar.is_token(text)
  return type(text) == "string" and string.find(text, grammar.TOKEN) ~= nil
end

--- Reports whether `text` is a valid field value for emission: no control character other than HTAB, and no DEL (RFC 9110,
--- section 5.5 allows HTAB, SP, VCHAR and obs-text; CR, LF and NUL in particular), so that a value
--- can never split a message (RFC 9110, section 5.5; RFC 9112, section 11).
---@param text any
---@return boolean
function grammar.is_field_value(text)
  return type(text) == "string" and string.find(text, "[%z\1-\8\10-\31\127]") == nil
end

--- Removes optional whitespace (SP and HTAB, RFC 9110 section 5.6.3) at both ends of `text`, in time linear in its
--- length: one search for the first other character and one for the last. A pattern with a lazy capture before a
--- class of whitespace anchored at the end (`^[ \t]*(.-)[ \t]*$`) is quadratic in the length of an inner run of
--- whitespace, which lets a peer spend the CPU of the reactor thread with one head.
---@param text string
---@return string
function grammar.trim_ows(text)
  local first = string.find(text, "[^ \t]")
  if first == nil then return "" end
  local last = string.match(text, "^.*()[^ \t]") --[[@as integer]]
  if first == 1 and last == #text then return text end
  return string.sub(text, first, last)
end

return grammar
