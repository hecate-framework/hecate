---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
local test = require("harness.test")
local openapi = require("hecate.openapi")
local T = test.Case("OpenApiProviderTest")

function T:test_provider_is_plain_data_with_defaults()
  local provider = openapi.provider { info = { title = "Shop", version = "1.0.0" } }
  self:assert_equal("openapi", provider.name)
  self:assert_equal("/openapi.json", provider.path)
  self:assert_equal("application/json", provider.media_type)
  self:assert_equal("function", type(provider.render))
end

function T:test_provider_options_are_checked()
  self:assert_error(function() openapi.provider {} end)
  self:assert_error(function() openapi.provider { info = { title = "x", version = "1" }, bogus = true } end)
end

function T:test_disabled_flag_is_carried()
  local provider = openapi.provider { info = { title = "Shop", version = "1.0.0" }, enabled = false, path = "/spec", name = "spec" }
  self:assert_equal(false, provider.enabled)
  self:assert_equal("/spec", provider.path)
end

return T
