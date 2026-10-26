-- Error classes of hecate.net. The roots (`NetworkError`, `ProtocolError`) live in `core`
-- (OQ-19); this package subclasses only for conditions callers handle differently.
global <const> require, tostring, ipairs, type, getmetatable, pcall, error

local core = require("hecate.core")

--- Raised when a stream ends in the middle of a read that needed more bytes.
---@class hecate.net.EndOfStreamError : hecate.core.NetworkError
---@field context { wanted?: integer, buffered: integer }  `buffered`: bytes kept in the reader
local EndOfStreamError = core.error_class("EndOfStreamError", "hecate.net.EndOfStreamError", core.NetworkError)

--- Raised when a TLS handshake or record fails: an untrusted or mismatched certificate (RFC 6125),
--- a protocol violation, an alert from the peer, a transport that ended without `close_notify`
--- (a truncation, RFC 8446 section 6.1), or a native TLS module that is not built.
---
--- `context.reason` (`hecate.net.TlsFailureReason`) tells the kinds apart without parsing the message:
--- `untrusted_issuer`, `name_mismatch`, `expired`, `not_yet_valid`, `revoked`, `alpn_mismatch`,
--- `truncated`, `transport_ended`, `stalled` or `native_missing`. It is absent when the failure is
--- not one of these (the operating system's verifier on macOS and Windows reports many failures
--- as text only).
---@class hecate.net.TlsError : hecate.core.NetworkError
---@field context { reason?: hecate.net.TlsFailureReason }
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

-- The `kind` of a native failure (`{ kind = ..., message = ... }`, derived from the rustls error
-- variant rather than its text) that is already a `context.reason`; any other kind is ignored.
local KINDS = {}
for _, entry in ipairs(REASONS) do KINDS[entry[2]] = true end
for _, reason in ipairs({ "truncated", "transport_ended", "stalled", "native_missing" }) do KINDS[reason] = true end

--- Builds a `TlsError` from a message, with `context.reason` given, taken from the `kind` of a
--- native failure table, or recognised in the text (the fallback).
---@param text string|{ kind?: string, message?: string }
---@param reason? hecate.net.TlsFailureReason
---@return hecate.net.TlsError
local function tls_failure(text, reason)
  if type(text) == "table" and getmetatable(text) == nil then
    if reason == nil and KINDS[text.kind] then reason = text.kind end
    text = text.message
  end
  text = tostring(text):gsub("\nstack traceback:.*$", "")
  if reason == nil then
    for _, entry in ipairs(REASONS) do
      if text:find(entry[1], 1, true) then reason = entry[2] break end
    end
  end
  return TlsError({ message = text, context = { reason = reason } })
end

--- Prefixes the message of a `TlsError` with the public call that raised it, as the caller wrote it
--- (coding-standards.md, "Errors"), replacing the prefix of an inner call. Other failures
--- (cancellations, transport failures, programmer errors) pass through untouched. Returns `failure`.
---@param failure any
---@param call string  for example `net.TlsStream.read`
---@return any
local function qualify(failure, call)
  if core.is_instance_of(failure, TlsError) then
    local text = (failure --[[@as hecate.net.TlsError]]).message
    text = text:gsub("^net%.[%w_.]+: ", "")
    ;(failure --[[@as hecate.net.TlsError]]).message = call .. ": " .. text
  end
  return failure
end

--- Renames the call a failure of a reactor function names: `reactor.connect_pipe: ...` raised under
--- `net.connect_pipe` becomes `net.connect_pipe: ...`, because the caller wrote the net call
--- (coding-standards.md, "Errors"). Failures that do not start with a reactor call pass through.
---@param failure any
---@param call string  the public net call
---@return any
local function rename(failure, call)
  if core.is_instance_of(failure, core.Error) then
    local text = (failure --[[@as hecate.core.Error]]).message
    if type(text) == "string" and text:find("^reactor%.[%w_.]+: ") then
      ;(failure --[[@as hecate.core.Error]]).message = call .. ": " .. text:gsub("^reactor%.[%w_.]+: ", "")
    end
  end
  return failure
end

--- Calls the reactor function `fn(...)` for the net call `call`, renaming the call in its failures.
---@param call string
---@param fn function
---@return any
local function delegate(call, fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then return result end
  error(rename(result, call), 0)
end

return { rename = rename, delegate = delegate, EndOfStreamError = EndOfStreamError, TlsError = TlsError, tls_failure = tls_failure, qualify = qualify }
