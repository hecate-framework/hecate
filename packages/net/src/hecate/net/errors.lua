-- Error classes of hecate.net. The roots (`NetworkError`, `ProtocolError`) live in `core`
-- (OQ-19); this package subclasses only for conditions callers handle differently.
global <const> require

local core = require("hecate.core")

--- Raised when a stream ends in the middle of a read that needed more bytes.
---@class hecate.net.EndOfStreamError : hecate.core.NetworkError
---@field context { wanted?: integer, buffered: integer }  `buffered`: bytes kept in the reader
local EndOfStreamError = core.error_class("EndOfStreamError", "hecate.net.EndOfStreamError", core.NetworkError)

--- Raised when a TLS handshake or record fails: an untrusted or mismatched certificate (RFC 6125),
--- a protocol violation, an alert from the peer, a transport that ended without `close_notify`
--- (a truncation, RFC 8446 section 6.1), or a native TLS module that is not built.
---@class hecate.net.TlsError : hecate.core.NetworkError
local TlsError = core.error_class("TlsError", "hecate.net.TlsError", core.NetworkError)

return { EndOfStreamError = EndOfStreamError, TlsError = TlsError }
