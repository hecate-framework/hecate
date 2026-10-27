-- Error classes of hecate.json. Every failure of the codec raises an instance of one of these
-- (ADR 0018, ADR 0020: one error hierarchy; both native modules report through it).
global <const> require

local core = require("hecate.core")

--- The root of the failures of the JSON codec: callers that do not care whether the text or the
--- value was at fault catch this class.
---@class hecate.json.JsonError : hecate.core.Error
local JsonError = core.error_class("JsonError", "hecate.json.JsonError")

--- Raised by `json.decode` when the text is not valid JSON text (RFC 8259) or exceeds a limit.
---
--- `context.reason` (`hecate.json.DecodeFailureReason`) tells the kinds apart without parsing the
--- message. `context.offset` is the number of bytes before the offending byte (0-based), `context.line`
--- the 1-based line (lines end at a line feed) and `context.column` the 1-based column of the
--- offending character on that line, counted in characters (code points), not bytes.
---@class hecate.json.DecodeError : hecate.json.JsonError
---@field context { reason: hecate.json.DecodeFailureReason, offset: integer, line: integer, column: integer }
local DecodeError = core.error_class("DecodeError", "hecate.json.DecodeError", JsonError)

--- Raised by `json.encode` when a Lua value has no JSON representation, or the output exceeds a limit.
---
--- `context.reason` (`hecate.json.EncodeFailureReason`) tells the kinds apart; `context.path` is the
--- JSON Pointer (RFC 6901) of the offending value inside the value passed to `encode` (the empty
--- string is the value itself).
---@class hecate.json.EncodeError : hecate.json.JsonError
---@field context { reason: hecate.json.EncodeFailureReason, path: string }
local EncodeError = core.error_class("EncodeError", "hecate.json.EncodeError", JsonError)

---@alias hecate.json.DecodeFailureReason
---| "syntax"  the text does not match the grammar of RFC 8259 (unexpected character, end of input, trailing content)
---| "invalid_utf8"  a string is not well-formed UTF-8 (RFC 8259 section 8.1)
---| "invalid_escape"  an unknown or truncated escape sequence in a string (section 7)
---| "lone_surrogate"  a `\u` escape of a surrogate that is not part of a valid pair (section 8.2, I-JSON)
---| "control_character"  an unescaped control character U+0000 to U+001F in a string (section 7)
---| "byte_order_mark"  the text starts with a byte order mark (section 8.1)
---| "duplicate_member_name"  an object has two members with the same name (section 4, I-JSON section 2.3)
---| "number_out_of_range"  a number that is not finite as a float
---| "depth_limit"  nesting deeper than `max_depth`
---| "size_limit"  input longer than `max_size`

---@alias hecate.json.EncodeFailureReason
---| "unsupported_type"  a function, userdata, thread or `nil` has no JSON representation
---| "integer_out_of_range"  an integer beyond +-2^53 with `canonical = "rfc8785"`, which writes numbers as IEEE doubles
---| "non_finite_number"  NaN and the infinities are not JSON numbers (RFC 8259 section 6)
---| "invalid_utf8"  a string or key is not well-formed UTF-8
---| "ambiguous_table"  a table that is neither a sequence nor an object (mixed or non-string keys)
---| "sparse_array"  a marked array with a hole or with keys that are not 1 to n
---| "depth_limit"  nesting deeper than `max_depth` (also raised for a cycle)
---| "size_limit"  output longer than `max_size`

return { JsonError = JsonError, DecodeError = DecodeError, EncodeError = EncodeError }
