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

return grammar
