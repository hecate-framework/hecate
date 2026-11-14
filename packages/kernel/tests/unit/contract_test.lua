---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
local test = require("harness.test")
local http = require("hecate.http")
local kernel = require("hecate.kernel")
local T = test.Case("ContractProviderTest")

local function get(serve, path)
  return serve(http.Request({ method = "GET", target = path, fields = http.Fields() }))
end

local function app(providers)
  local m = kernel.routes("health")
  m:get("/health", { name = "health", action = function() return { ok = true } end })
  return kernel.Application({ routes = { m }, contracts = providers })
end

function T:test_provider_is_served_with_its_media_type_and_sees_only_application_routes()
  local seen
  local a = app { { name = "doc", path = "/doc", media_type = "text/plain", render = function(entries) seen = entries; return "hello" end } }
  local serve = a:boot()
  local response = get(serve, "/doc")
  self:assert_equal(200, response.status)
  self:assert_equal("hello", response.content)
  self:assert_equal("text/plain", response.fields:get("Content-Type"))
  self:assert_equal(1, #seen)
  self:assert_equal("health", seen[1].name)
  self:assert_equal(1, #a.entries)
end

function T:test_document_is_rendered_once()
  local count = 0
  local serve = app({ { name = "doc", path = "/doc", media_type = "text/plain", render = function() count = count + 1; return "x" end } }):boot()
  get(serve, "/doc"); get(serve, "/doc")
  self:assert_equal(1, count)
end

function T:test_disabled_provider_serves_nothing()
  local serve = app({ { name = "doc", path = "/doc", media_type = "text/plain", render = function() return "x" end, enabled = false } }):boot()
  self:assert_equal(404, get(serve, "/doc").status)
end

function T:test_invalid_provider_is_refused()
  self:assert_error(function() app({ { name = "doc", path = "/doc", media_type = "text/plain" } }):boot() end)
  self:assert_error(function() app({ { name = "doc", path = "/doc", media_type = "x", render = function() end, bogus = 1 } }):boot() end)
end

return T
