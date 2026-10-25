-- The backend seam of hecate.json (ADR 0020, "One public API").
--
-- The codec runs on two native modules, both required at run time (OQ-53: there is no fallback backend):
--
--   * `hecate.json.native`: the decoder (C over vendored yyjson, built by `lua tools/run.lua build-native json`
--     or by LuaRocks). `native.bind(markers)` is called once, so that the native code holds the very `null`
--     and metatables of the Lua side (identity is part of the value model).
--   * `hecate.json.encoder_native`: the encoder (Rust, `serde_json` through `mlua`, ADR 0021), bound to the same
--     markers.
--
-- The backend is a table with `decode(text, options)` and `encode(value, options)`:
--
--   decode(text, options) -> value | nil, failure     options: { max_depth, max_size }
--   encode(value, options) -> text | nil, failure     options: { max_depth, max_size, indent?, canonical, rfc8785 }
--
-- `rfc8785` (implies `canonical`, never combined with `indent`) selects RFC 8785 (JCS): every number is written as
-- an IEEE double in the ECMAScript format, and an integer beyond +-2^53 is a failure. A `failure` is
-- `{ reason, message, offset? }` for decoding (offset: bytes before the offending byte; absent for a duplicate member
-- name) and `{ reason, message, path }` for encoding (path: an RFC 6901 JSON Pointer). Options arrive validated and
-- complete; the public module (`hecate.json`) owns validation, the construction of error objects and the line and
-- column of a decoding failure.
--
-- The modules are looked up on first use, never at `require` time (coding-standards.md, "Modules"). A module that is
-- absent raises a `JsonError` that names the build command; a module that is present but fails to load raises its own
-- error, so that a broken build is never mistaken for a missing one.
global <const> require, pcall, type, error

local errors = require("hecate.json.errors")
local markers = require("hecate.json.internal.markers")

local NATIVE = "hecate.json.native"
local ENCODER = "hecate.json.encoder_native"
local BUILD_COMMAND = "lua tools/run.lua build-native json"

local M = {}

---@type { decode: function, encode: function }?
local selected

--- Requires a native module of the codec.
---@param name string
---@return table module
local function load_module(name)
  local loaded, module = pcall(require, name)
  if loaded then return module end
  if type(module) == "string" and module:find(("module '%s' not found"):format(name), 1, true) then
    error(errors.JsonError({
      message = ("the native module %s is not built: run `%s` (hecate.json has no pure-Lua fallback)"):format(
        name, BUILD_COMMAND),
      context = { module = name, command = BUILD_COMMAND },
    }), 0)
  end
  error(module, 0)
end

--- Returns the backend, loading and binding the native modules on first use.
---@return { decode: function, encode: function } backend
function M.get()
  if selected then return selected end
  local native = load_module(NATIVE)
  if type(native) ~= "table" or type(native.decode) ~= "function" then
    error(("%s does not provide decode"):format(NATIVE), 0)
  end
  local encoder = load_module(ENCODER)
  if type(encoder) ~= "table" or type(encoder.encode) ~= "function" or type(encoder.bind) ~= "function" then
    error(("%s does not provide bind and encode"):format(ENCODER), 0)
  end
  if type(native.bind) == "function" then native.bind(markers) end
  encoder.bind(markers)
  selected = { decode = native.decode, encode = encoder.encode }
  return selected
end

--- Forgets the selected backend so that the next call loads again (tests, after a native build).
function M.reset()
  selected = nil
end

return M
