-- The binding contract of the native decoder (csrc/native.c): the value model it builds, the markers it is bound to,
-- the limits it applies and the arguments it checks. The values and failures it gives for texts are pinned by the
-- fixtures (decode_fixtures_test.lua) and the shared behaviour tests (decode_test.lua).
-- The native module is required at run time: a module that is not built fails the file with the build command.
local test = require("harness.test")
local backend = require("hecate.json.internal.backend")
local markers = require("hecate.json.internal.markers")
local T = test.Case("JsonNativeTest")

local built, native = pcall(require, "hecate.json.native")

local OPTIONS = { max_depth = 1000, max_size = 16 * 1024 * 1024 }

function T:set_up()
  if not built then self:fail("hecate.json.native is not built: run `lua tools/run.lua build-native json`\n" .. tostring(native)) end
end

function T:test_decoded_containers_carry_the_markers_and_null_is_the_lua_value()
  local value = native.decode('{"a":[],"b":{},"c":null,"d":[null]}', OPTIONS)
  self:assert_true(getmetatable(value) == markers.object_metatable)
  self:assert_true(getmetatable(value.a) == markers.array_metatable)
  self:assert_true(getmetatable(value.b) == markers.object_metatable)
  self:assert_true(value.c == markers.null)
  self:assert_true(value.d[1] == markers.null)
end

function T:test_bind_keeps_the_markers_it_is_given()
  local array_metatable, object_metatable = {}, {}
  local null = setmetatable({}, { __metatable = "other null" })
  native.bind({ null = null, array_metatable = array_metatable, object_metatable = object_metatable })
  local value = native.decode('{"a":[null]}', OPTIONS)
  local ok, err = pcall(function()
    self:assert_true(getmetatable(value) == object_metatable)
    self:assert_true(getmetatable(value.a) == array_metatable)
    self:assert_true(value.a[1] == null)
  end)
  native.bind(markers)
  if not ok then error(err, 0) end
  self:assert_true(getmetatable(native.decode("[]", OPTIONS)) == markers.array_metatable)
  self:assert_error(function() native.bind({}) end)
  self:assert_error(function() native.bind(nil) end)
end

function T:test_the_module_decodes_before_bind_is_called_and_does_not_encode()
  self:assert_equal("function", type(native.decode))
  self:assert_nil(native.encode, "encoding is the Rust module's: hecate.json.encoder_native")
  self:assert_nil(package.loaded["hecate.json.internal.reference"], "no Lua code answers for the native decoder")
end

function T:test_binary_safe_strings_and_members()
  local value = native.decode('{"a\\u0000b":"x\\u0000y"}', OPTIONS)
  self:assert_equal("x\0y", value["a\0b"])
  self:assert_error(function() native.decode({}, OPTIONS) end)
  self:assert_error(function() native.decode("1") end)
end

function T:test_a_deep_text_is_decoded_up_to_the_depth_ceiling_and_rejected_beyond()
  local deep = 1000
  local text = ("["):rep(deep) .. ("]"):rep(deep)
  local value = native.decode(text, { max_depth = deep, max_size = #text })
  self:assert_true(getmetatable(value) == markers.array_metatable)
  local failure
  value, failure = native.decode(text, { max_depth = deep - 1, max_size = #text })
  self:assert_nil(value)
  self:assert_equal("depth_limit", failure.reason)
  self:assert_equal(deep - 1, failure.offset)
  value, failure = native.decode(("["):rep(100000), { max_depth = 1000, max_size = 200000 })
  self:assert_nil(value)
  self:assert_equal("depth_limit", failure.reason)
  self:assert_equal(1000, failure.offset)
end

function T:test_a_failure_is_a_table_and_a_value_is_never_returned_with_it()
  local value, failure = native.decode("[1,", OPTIONS)
  self:assert_nil(value)
  self:assert_equal("syntax", failure.reason)
  self:assert_equal(3, failure.offset)
  self:assert_equal("string", type(failure.message))
  local ok, none = native.decode("[1]", OPTIONS)
  self:assert_not_nil(ok)
  self:assert_nil(none)
end

function T:test_the_backend_selects_the_native_modules_and_binds_them_to_the_markers()
  backend.reset()
  local selected = backend.get()
  self:assert_true(selected.decode == native.decode)
  self:assert_equal("function", type(selected.encode))
  self:assert_true(backend.get() == selected, "the selection is cached")
  backend.reset()
end

return T
