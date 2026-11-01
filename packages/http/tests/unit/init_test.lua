---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests hide a module on purpose
local test = require("harness.test")
local T = test.Case("InitTest")

function T:test_the_message_model_loads_without_the_native_module()
  local saved = {}
  for name, module in pairs(package.loaded) do
    if name == "hecate.http" or name:find("^hecate%.http%.") then saved[name] = module end
  end
  for name in pairs(saved) do package.loaded[name] = nil end
  local preload = package.preload["hecate.http.native"]
  package.preload["hecate.http.native"] = function() error("module 'hecate.http.native' not found: hidden by the test") end
  local ok, http = pcall(require, "hecate.http")
  package.preload["hecate.http.native"] = preload
  local fields, available, reason, parse_error
  if ok then
    fields = http.Fields({ { "A", "1" } }):get("a")
    available, reason = http.available()
    parse_error = http.ParseError
    self:assert_nil(http.Server)
    self:assert_nil(http.Client)
    self:assert_nil(http.Parser)
    self:assert_equal("a=1&b=2", http.form.encode_urlencoded({ { "a", "1" }, { "b", "2" } }))
    self:assert_equal(400, http.problem.response(400).status)
  end
  for name in pairs(package.loaded) do
    if name == "hecate.http" or name:find("^hecate%.http%.") then package.loaded[name] = nil end
  end
  for name, module in pairs(saved) do package.loaded[name] = module end
  self:assert_true(ok, tostring(http))
  self:assert_equal("1", fields)
  self:assert_false(available)
  self:assert_equal("string", type(reason))
  self:assert_nil(reason:find("\n"), "one line")
  self:assert_not_nil(reason:find("lua tools/run.lua build-native http", 1, true), "the command that fixes it")
  self:assert_not_nil(parse_error)
end

function T:test_with_the_native_module_the_server_the_client_and_the_parser_exist()
  local http = require("hecate.http")
  self:assert_true(http.available())
  self:assert_not_nil(http.Server)
  self:assert_not_nil(http.Client)
  self:assert_not_nil(http.Parser)
  local core = require("hecate.core")
  self:assert_true(core.is_instance_of(http.Parser.request():feed("x\r\n\r\n") and select(2, http.Parser.request():feed("x\r\n\r\n")) or http.ParseError({ message = "x" }), core.ProtocolError))
end

return T
