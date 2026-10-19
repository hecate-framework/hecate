-- The backend seam: lazy selection of hecate.json.native, fallback to the reference backend, and
-- the shared contract (markers, failures as values).
local test = require("harness.test")
local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")
local reference = require("hecate.json.internal.reference")
local markers = require("hecate.json.internal.markers")
local T = test.Case("JsonBackendTest")

local NATIVE = "hecate.json.native"

function T:set_up()
  self.preload = package.preload[NATIVE]
  self.loaded = package.loaded[NATIVE]
  backend.reset()
end

function T:tear_down()
  package.preload[NATIVE] = self.preload
  package.loaded[NATIVE] = self.loaded
  backend.reset()
end

function T:test_requiring_the_module_does_not_load_the_native_backend()
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = function() error("loaded at require time") end
  package.loaded["hecate.json"] = nil
  local fresh = require("hecate.json")
  self:assert_not_nil(fresh.encode)
  package.loaded["hecate.json"] = json
end

function T:test_without_a_native_module_the_reference_backend_is_used()
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = nil
  local selected, name = backend.get()
  if name == "reference" then self:assert_true(selected == reference) end
  self:assert_equal("[1]", json.encode({ 1 }))
  local again, again_name = backend.get()
  self:assert_true(again == selected and again_name == name, "the selection is cached")
end

function T:test_a_native_module_is_preferred_bound_to_the_markers_and_used_by_the_public_api()
  local calls = {}
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = function()
    return {
      bind = function(bound) calls.bound = bound end,
      decode = function(text, options) calls.decode = options return "decoded:" .. text end,
      encode = function(value, options) calls.encode = options return "encoded" end,
    }
  end
  self:assert_equal("decoded:x", json.decode("x", { max_depth = 7 }))
  self:assert_equal("encoded", json.encode({}, { pretty = true, canonical = true }))
  self:assert_true(calls.bound.null == json.null)
  self:assert_true(calls.bound.array_metatable ~= nil and calls.bound.object_metatable ~= nil)
  self:assert_equal(7, calls.decode.max_depth)
  self:assert_equal(16 * 1024 * 1024, calls.decode.max_size)
  self:assert_equal("  ", calls.encode.indent)
  self:assert_true(calls.encode.canonical)
  self:assert_equal("native", select(2, backend.get()))
end

function T:test_native_failures_become_the_same_errors_with_computed_positions()
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = function()
    return {
      decode = function() return nil, { reason = "syntax", message = "boom", offset = 4 } end,
      encode = function() return nil, { reason = "unsupported_type", message = "bad", path = "/a" } end,
    }
  end
  local err = self:assert_error(function() json.decode("ab\ncd\n") end)
  self:assert_equal("hecate.json.DecodeError", err.code)
  self:assert_equal(2, err.context.line)
  self:assert_equal(2, err.context.column)
  self:assert_equal(4, err.context.offset)
  local encode_err = self:assert_error(function() json.encode(1) end)
  self:assert_equal("hecate.json.EncodeError", encode_err.code)
  self:assert_equal("/a", encode_err.context.path)
end

function T:test_a_native_module_that_fails_to_load_is_not_hidden_by_the_fallback()
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = function() error("undefined symbol: yyjson_read", 0) end
  local err = self:assert_error(function() return json.decode("1") end)
  self:assert_true(tostring(err):find("undefined symbol", 1, true) ~= nil, tostring(err))
end

function T:test_a_native_module_without_the_contract_is_rejected()
  package.loaded[NATIVE] = nil
  package.preload[NATIVE] = function() return { decode = function() end } end
  self:assert_error(function() return json.decode("1") end, "does not provide")
end

function T:test_the_reference_backend_returns_failures_instead_of_raising()
  local options = { max_depth = 1000, max_size = 1000 }
  local value, failure = reference.decode("[1,", options)
  self:assert_nil(value)
  assert(failure)
  self:assert_equal("syntax", failure.reason)
  self:assert_equal(3, failure.offset)
  local text, encode_failure = reference.encode(0 / 0, { max_depth = 10, max_size = 100, canonical = false })
  self:assert_nil(text)
  assert(encode_failure)
  self:assert_equal("non_finite_number", encode_failure.reason)
  self:assert_equal("", encode_failure.path)
  local decoded = reference.decode("[]", options)
  self:assert_true(getmetatable(decoded) == markers.array_metatable)
end

return T
