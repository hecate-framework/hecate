-- Error classes of hecate.net. The roots (`NetworkError`, `ProtocolError`) live in `core`
-- (OQ-19); this package subclasses only for conditions callers handle differently.
global <const> require, tostring, ipairs

local core = require("hecate.core")

--- Raised when a stream ends in the middle of a read that needed more bytes.
---@class hecate.net.EndOfStreamError : hecate.core.NetworkError
---@field context { wanted?: integer, buffered: integer }  `buffered`: bytes kept in the reader
local EndOfStreamError = core.error_class("EndOfStreamError", "hecate.net.EndOfStreamError", core.NetworkError)

--- Raised when a TLS handshake or record fails: an untrusted or mismatched certificate (RFC 6125),
--- a protocol violation, an alert from the peer, a transport that ended without `close_notify`
--- (a truncation, RFC 8446 section 6.1), or a native TLS module that is not built.
---
--- `context.reason` tells the kinds apart without parsing the message: `untrusted_issuer`,
--- `name_mismatch`, `expired`, `not_yet_valid`, `revoked`, `alpn_mismatch`, `truncated`,
--- `transport_ended`, `stalled` or `native_missing`. It is absent when the failure is not one of
--- these (the operating system's verifier on macOS and Windows reports many failures as text only).
---@class hecate.net.TlsError : hecate.core.NetworkError
---@field context { reason?: string }
local TlsError = core.error_class("TlsError", "hecate.net.TlsError", core.NetworkError)

-- How rustls words certificate failures (checked against rustls 0.23.46), in the order tried.
local REASONS = {
  { "UnknownIssuer", "untrusted_issuer" },
  { "not valid for name", "name_mismatch" },
  { "not valid yet", "not_yet_valid" },
  { "certificate expired", "expired" },
  { "certificate revoked", "revoked" },
  { "NoApplicationProtocol", "alpn_mismatch" },
}

--- Builds a `TlsError` from a message, with `context.reason` given or recognised in the text.
---@param text string
---@param reason? string
---@return hecate.net.TlsError
local function tls_failure(text, reason)
  text = tostring(text)
  if reason == nil then
    for _, entry in ipairs(REASONS) do
      if text:find(entry[1], 1, true) then reason = entry[2] break end
    end
  end
  return TlsError({ message = text, context = { reason = reason } })
end

return { EndOfStreamError = EndOfStreamError, TlsError = TlsError, tls_failure = tls_failure }
