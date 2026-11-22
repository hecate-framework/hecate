-- Error classes of hecate.unicode (ADR 0018: one hierarchy; ADR 0032).
global <const> require

local core = require("hecate.core")

--- The root of the failures of the Unicode algorithms: callers that do not care which one failed catch this class.
---@class hecate.unicode.UnicodeError : hecate.core.Error
local UnicodeError = core.error_class("UnicodeError", "hecate.unicode.UnicodeError")

--- Raised when a string given to a function of `hecate.unicode` is not well-formed UTF-8 (Unicode Standard 3.9,
--- Table 3-7: no overlong form, no surrogate, nothing above U+10FFFF). `context.position` is the 1-based byte
--- position of the first byte that is not valid.
---@class hecate.unicode.InvalidUtf8Error : hecate.unicode.UnicodeError
---@field context { position: integer }
local InvalidUtf8Error = core.error_class("InvalidUtf8Error", "hecate.unicode.InvalidUtf8Error", UnicodeError)

--- Raised when the installed `hecate-unicode-data` has a table layout (`format`) that this version of `hecate-unicode`
--- does not know, for example a data rock newer than the algorithms. `context.format` is the layout found,
--- `context.supported` the list of layouts known and `context.unicode_version` the Unicode version of the data.
---@class hecate.unicode.DataFormatError : hecate.unicode.UnicodeError
---@field context { format: any, supported: integer[], unicode_version: any }
local DataFormatError = core.error_class("DataFormatError", "hecate.unicode.DataFormatError", UnicodeError)

return {
  UnicodeError = UnicodeError,
  InvalidUtf8Error = InvalidUtf8Error,
  DataFormatError = DataFormatError,
}
