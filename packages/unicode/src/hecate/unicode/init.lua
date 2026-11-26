-- hecate.unicode: normalisation of UTF-8 strings, NFC and NFD (Unicode Standard 3.11 and UAX #15), over the tables of the
-- rock `hecate-unicode-data` (ADR 0032, packages/unicode/README.md). Pure Lua, no I/O.
global <const> require, type, error, utf8

local core = require("hecate.core")
local errors = require("hecate.unicode.errors")
local tables = require("hecate.unicode.internal.tables")
local algorithm = require("hecate.unicode.internal.algorithm")
local data = require("hecate.unicode_data")

local ArgumentError = core.ArgumentError

--- Normalisation of UTF-8 strings: `nfc`, `nfd`, `is_nfc`, `is_nfd`, the `unicode_version` in use and the errors.
---@class hecate.unicode
---@field version string  the version of this package, the version of Hecate (`VERSION`, ADR 0005)
---@field unicode_version string  the Unicode version of the installed `hecate-unicode-data`, for example "18.0.0"
---@field UnicodeError hecate.unicode.UnicodeError
---@field InvalidUtf8Error hecate.unicode.InvalidUtf8Error
---@field DataFormatError hecate.unicode.DataFormatError
local unicode = {
  version = "0.0.0",
  unicode_version = data.unicode_version,
  UnicodeError = errors.UnicodeError,
  InvalidUtf8Error = errors.InvalidUtf8Error,
  DataFormatError = errors.DataFormatError,
}

--- Checks that `text` is a string of well-formed UTF-8; otherwise raises.
---@param text any
---@param name string  the function, for the message
local function check(text, name)
  if type(text) ~= "string" then
    error(ArgumentError({ message = ("%s expects a string, got %s"):format(name, type(text)), context = { argument = "text" } }), 3)
  end
  -- ASCII is well-formed UTF-8 and needs no scan.
  if not text:find("[\128-\255]") then return end
  local length, position = utf8.len(text)
  if not length then
    error(errors.InvalidUtf8Error({
      message = ("%s: the string is not well-formed UTF-8 (byte %d)"):format(name, position),
      context = { position = position },
    }), 3)
  end
end

--- Normalisation Form C: canonical decomposition, canonical ordering, then canonical composition (UAX #15). Code points
--- that are unassigned in the Unicode version in use pass through unchanged. A string without a byte above 0x7F is
--- returned as it is.
---@param text string  well-formed UTF-8
---@return string
function unicode.nfc(text)
  check(text, "nfc")
  return algorithm.normalise(text, true, tables.get())
end

--- Normalisation Form D: full canonical decomposition and canonical ordering (UAX #15).
---@param text string  well-formed UTF-8
---@return string
function unicode.nfd(text)
  check(text, "nfd")
  return algorithm.normalise(text, false, tables.get())
end

--- True when `text` is in Normalisation Form C. This normalises and compares: it costs as much as `nfc`.
---@param text string  well-formed UTF-8
---@return boolean
function unicode.is_nfc(text)
  check(text, "is_nfc")
  return algorithm.normalise(text, true, tables.get()) == text
end

--- True when `text` is in Normalisation Form D. This normalises and compares: it costs as much as `nfd`.
---@param text string  well-formed UTF-8
---@return boolean
function unicode.is_nfd(text)
  check(text, "is_nfd")
  return algorithm.normalise(text, false, tables.get()) == text
end

return unicode
