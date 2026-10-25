-- The backend seam: lazy loading of the two native modules (the decoder `hecate.json.native`, the encoder
-- `hecate.json.encoder_native`), the clear error of a module that is not built, and the shared contract
-- (markers, failures as values). There is no fallback backend (OQ-53).
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")
local T = test.Case("JsonBackendTest")

local NATIVE = "hecate.json.native"
local ENCODER = "hecate.json.encoder_native"

local function missing(name)
  return function() error(("module '%s' not found"):format(name), 0) end
end

function T:set_up()
  self.preload = { [NATIVE] = package.preload[NATIVE], [ENCODER] = package.preload[ENCODER] }
  self.loaded = { [NATIVE] = package.loaded[NATIVE], [ENCODER] = package.loaded[ENCODER] }
  backend.reset()
end

function T:tear_down()
  for _, name in ipairs({ NATIVE, ENCODER }) do
    package.preload[name] = self.preload[name]
    package.loaded[name] = self.loaded[name]
  end
  backend.reset()
end

-- Installs fake modules; `nil` for a module leaves the real one out of reach (it is reported as not found).
local function install(native, encoder)
  package.loaded[NATIVE], package.loaded[ENCODER] = nil, nil
  package.preload[NATIVE] = native and function() return native end or missing(NATIVE)
  package.preload[ENCODER] = encoder and function() return encoder end or missing(ENCODER)
end

function T:test_requiring_the_module_does_not_load_the_native_modules()
  package.loaded[NATIVE], package.loaded[ENCODER] = nil, nil
  package.preload[NATIVE] = function() error("loaded at require time") end
  package.preload[ENCODER] = function() error("loaded at require time") end
  package.loaded["hecate.json"] = nil
  local fresh = require("hecate.json")
  self:assert_not_nil(fresh.encode)
  package.loaded["hecate.json"] = json
end

function T:test_a_missing_decoder_raises_an_error_that_names_the_build_command()
  install(nil, { bind = function() end, encode = function() end })
  local err = self:assert_error(function() return json.decode("1") end)
  self:assert_true(core.is_instance_of(err, json.JsonError), tostring(err))
  self:assert_true(tostring(err):find("lua tools/run.lua build-native json", 1, true) ~= nil, tostring(err))
  self:assert_true(tostring(err):find(NATIVE, 1, true) ~= nil, tostring(err))
  self:assert_equal("lua tools/run.lua build-native json", err.context.command)
end

function T:test_a_missing_encoder_raises_an_error_that_names_the_build_command()
  install({ decode = function() end }, nil)
  local err = self:assert_error(function() return json.encode(1) end)
  self:assert_true(core.is_instance_of(err, json.JsonError), tostring(err))
  self:assert_true(tostring(err):find("lua tools/run.lua build-native json", 1, true) ~= nil, tostring(err))
  self:assert_true(tostring(err):find(ENCODER, 1, true) ~= nil, tostring(err))
end

function T:test_there_is_no_fallback_backend()
  self:assert_nil(package.loaded["hecate.json.internal.reference"])
  self:assert_false(pcall(require, "hecate.json.internal.reference"))
  self:assert_nil(backend.use)
end

function T:test_the_native_modules_are_bound_to_the_markers_and_used_by_the_public_api()
  local calls = {}
  install({
    bind = function(bound) calls.native_bound = bound end,
    decode = function(text, options) calls.decode = options return "decoded:" .. text end,
  }, {
    bind = function(bound) calls.encoder_bound = bound end,
    encode = function(value, options) calls.encode = options return "encoded" end,
  })
  self:assert_equal("decoded:x", json.decode("x", { max_depth = 7 }))
  self:assert_equal("encoded", json.encode({}, { pretty = true, canonical = true }))
  self:assert_true(calls.native_bound.null == json.null)
  self:assert_true(calls.encoder_bound.null == json.null)
  self:assert_true(calls.encoder_bound.array_metatable ~= nil and calls.encoder_bound.object_metatable ~= nil)
  self:assert_equal(7, calls.decode.max_depth)
  self:assert_equal(16 * 1024 * 1024, calls.decode.max_size)
  self:assert_equal("  ", calls.encode.indent)
  self:assert_true(calls.encode.canonical)
  self:assert_false(calls.encode.rfc8785)
  self:assert_true(backend.get() == backend.get(), "the selection is cached")
end

function T:test_rfc8785_goes_to_the_encoder_with_its_flag()
  local seen
  install({ decode = function() end }, { bind = function() end, encode = function(_, options) seen = options return "2" end })
  self:assert_equal("2", json.encode(2, { canonical = "rfc8785" }))
  self:assert_true(seen.rfc8785 and seen.canonical)
end

function T:test_a_native_module_that_fails_to_load_is_reported_as_it_is()
  package.loaded[NATIVE], package.loaded[ENCODER] = nil, nil
  package.preload[NATIVE] = function() error("undefined symbol: yyjson_read", 0) end
  local err = self:assert_error(function() return json.decode("1") end)
  self:assert_true(tostring(err):find("undefined symbol", 1, true) ~= nil, tostring(err))
  self:assert_nil(tostring(err):find("build-native", 1, true), "a broken build is not a missing one")
end

function T:test_an_encoder_that_fails_to_load_is_reported_as_it_is()
  package.loaded[NATIVE], package.loaded[ENCODER] = nil, nil
  package.preload[NATIVE] = function() return { decode = function() end } end
  package.preload[ENCODER] = function() error("boom", 0) end
  local err = self:assert_error(function() backend.get() end)
  self:assert_true(tostring(err):find("boom", 1, true) ~= nil)
end

function T:test_failures_become_the_same_errors_with_computed_positions()
  install({
    decode = function() return nil, { reason = "syntax", message = "boom", offset = 4 } end,
  }, {
    bind = function() end,
    encode = function() return nil, { reason = "unsupported_type", message = "bad", path = "/a" } end,
  })
  local err = self:assert_error(function() json.decode("ab\ncd\n") end)
  self:assert_equal("hecate.json.DecodeError", err.code)
  self:assert_equal(2, err.context.line)
  self:assert_equal(2, err.context.column)
  self:assert_equal(4, err.context.offset)
  local encode_err = self:assert_error(function() json.encode(1) end)
  self:assert_equal("hecate.json.EncodeError", encode_err.code)
  self:assert_equal("/a", encode_err.context.path)
end

function T:test_a_module_without_the_contract_is_rejected()
  install({ decode = function() end }, { bind = function() end })
  self:assert_error(function() return json.decode("1") end, "does not provide")
  install({ bind = function() end }, { bind = function() end, encode = function() end })
  backend.reset()
  self:assert_error(function() return json.decode("1") end, "does not provide")
end

function T:test_the_real_modules_return_failures_instead_of_raising()
  package.loaded[NATIVE], package.loaded[ENCODER] = self.loaded[NATIVE], self.loaded[ENCODER]
  package.preload[NATIVE], package.preload[ENCODER] = self.preload[NATIVE], self.preload[ENCODER]
  backend.reset()
  local selected = backend.get()
  local value, failure = selected.decode("[1,", { max_depth = 1000, max_size = 1000 })
  self:assert_nil(value)
  self:assert_equal("syntax", failure.reason)
  self:assert_equal(3, failure.offset)
  local text, encode_failure = selected.encode(0 / 0, { max_depth = 10, max_size = 100, canonical = false, rfc8785 = false })
  self:assert_nil(text)
  self:assert_equal("non_finite_number", encode_failure.reason)
  self:assert_equal("", encode_failure.path)
end

return T
