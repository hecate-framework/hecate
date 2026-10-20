-- The backend seam of hecate.json (ADR 0020, "One public API").
--
-- A backend is a table with `decode(text, options)` and `encode(value, options)` that follow the
-- contract documented in `hecate.json.internal.reference`: the same value model (the markers of
-- `hecate.json.internal.markers`), the same failure reasons, options already validated, failures
-- returned as `nil, failure` instead of raised. Two backends exist:
--
--   * `hecate.json.native`: the native module (C, built by `lua tools/run.lua build-native json` or by
--     LuaRocks): yyjson decoder; its own `encode` delegates to the reference backend, the Rust
--     encoder below replaces it. When it is loaded, `native.bind(markers)` is called once if it exists, so that the native code
--     holds the very `null` and metatables of the Lua side (identity is part of the value model).
--     The Rust encoder (`hecate.json.encoder_native`, `serde_json` through `mlua`, ADR 0021) is optional and loaded with it: it returns
--     `nil` for everything it does not encode itself (failures, `rfc8785`), and the reference encoder then
--     answers, so the failure reasons exist once.
--   * `hecate.json.internal.reference`: pure Lua, the fallback and the test oracle.
--
-- The native module is looked up on first use, never at `require` time (coding-standards.md, "Modules").
-- A module that is absent selects the reference backend; a module that is present but fails to load
-- raises, so that a broken build is never hidden behind the slower fallback.
global <const> require, pcall, type, error

local markers = require("hecate.json.internal.markers")

local NATIVE = "hecate.json.native"
local ENCODER = "hecate.json.encoder_native"

local M = {}

---@type table?
local selected
---@type "native"|"reference"|nil
local selected_name

--- Wraps the native backend with the Rust encoder when that module is built. A module that is present
--- but fails to load raises, as for the native decoder.
---@param native table
---@return table backend
local function with_encoder(native)
  local loaded, encoder = pcall(require, ENCODER)
  if not loaded then
    if type(encoder) == "string" and encoder:find(("module '%s' not found"):format(ENCODER), 1, true) then
      return native
    end
    error(encoder, 0)
  end
  encoder.bind(markers)
  local reference = require("hecate.json.internal.reference")
  local encode = encoder.encode
  return {
    decode = native.decode,
    encode = function(value, options)
      if not options.rfc8785 then
        local text = encode(value, options)
        if text ~= nil then return text end
      end
      return reference.encode(value, options)
    end,
  }
end

--- Returns the active backend, selecting it on first use.
---@return table backend
---@return "native"|"reference" name
function M.get()
  if selected then return selected, selected_name --[[@as "native"|"reference"]] end
  local loaded, native = pcall(require, NATIVE)
  if loaded then
    if type(native) ~= "table" or type(native.decode) ~= "function" or type(native.encode) ~= "function" then
      error(("%s does not provide decode and encode"):format(NATIVE), 0)
    end
    if type(native.bind) == "function" then native.bind(markers) end
    selected, selected_name = with_encoder(native), "native"
  elseif type(native) == "string" and native:find(("module '%s' not found"):format(NATIVE), 1, true) then
    selected, selected_name = require("hecate.json.internal.reference"), "reference"
  else
    error(native, 0)
  end
  return selected, selected_name
end

--- Forces a backend (tests: the shared suites run against both). `"native"` raises when the module is
--- not built; `"reference"` never loads the native module; `nil` forgets the choice, as `reset` does.
---@param name "native"|"reference"|nil
function M.use(name)
  if name == nil then
    selected, selected_name = nil, nil
  elseif name == "reference" then
    selected, selected_name = require("hecate.json.internal.reference"), "reference"
  elseif name == "native" then
    local native = require(NATIVE)
    if type(native.bind) == "function" then native.bind(markers) end
    selected, selected_name = with_encoder(native), "native"
  else
    error(("unknown backend %q"):format(name), 2)
  end
end

--- Forgets the selected backend so that the next call selects again (tests, after a native build).
function M.reset()
  selected, selected_name = nil, nil
end

return M
