-- The error classes of the HTTP package that need no native module.
global <const> require

local core = require("hecate.core")

--- A message that is not valid HTTP/1.1, or that exceeds a limit of the parser.
---
--- `context.reason` is the stable identifier of the failure (`target_too_long`, `field_name_too_large`,
--- `field_value_too_large`, `reason_too_long`, `head_too_large`, `too_many_fields`, `chunked_in_http_1_0`,
--- `unsupported_version`, `unsupported_method`, `unsupported_protocol`, `out_of_memory`, `no_progress` (an internal
--- failure: the native parser consumed nothing and reported nothing; status 500, the parser is terminal), `upgraded`,
--- or, for llhttp's own rejections, the lowercase name of its error code without the `HPE_` prefix, for example
--- `invalid_method`), `context.detail` the text llhttp gives (informational: never match on it), `context.code` the
--- llhttp error name, `context.position` the 0-based offset in the chunk of the call that failed, and `context.status`
--- the status code to answer with: 414 for a request target over its limit, 431 for a field, a head or a field count over
--- its limit, 400 otherwise (RFC 9110 sections 15.5.1, 15.5.15 and 15.5.32). After an upgrade, `feed` and `finish`
--- return a ParseError with the reason `upgraded`: the bytes after the upgrade are not HTTP.
---@class hecate.http.ParseError : hecate.core.ProtocolError
---@field context { reason: string, detail: string, code: string, position: integer, status: integer }
local ParseError = core.error_class("ParseError", "hecate.http.ParseError", core.ProtocolError)

return { ParseError = ParseError }
