-- Error classes of hecate.net. The roots (`NetworkError`, `ProtocolError`) live in `core`
-- (OQ-19); this package subclasses only for conditions callers handle differently.
global <const> require

local core = require("hecate.core")

---@class hecate.net.EndOfStreamError : hecate.core.NetworkError
---@field context { wanted?: integer, buffered: integer }  `buffered`: bytes kept in the reader
local EndOfStreamError = core.error_class("EndOfStreamError", "hecate.net.EndOfStreamError", core.NetworkError)

return { EndOfStreamError = EndOfStreamError }
