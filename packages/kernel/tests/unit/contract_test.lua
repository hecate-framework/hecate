---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
local test = require("harness.test")
local http = require("hecate.http")
local json = require("hecate.json")
local kernel = require("hecate.kernel")
local T = test.Case("ServedOpenApiTest")

local INFO = { title = "Shop", version = "1.0.0" }

local function get(serve, path)
  return serve(http.Request({ method = "GET", target = path, fields = http.Fields() }))
end

local function app(openapi)
  local m = kernel.routes("health")
  m:get("/health", { name = "health", responses = { [204] = true }, action = function() return kernel.respond(204) end })
  return kernel.Application({ routes = { m }, openapi = openapi })
end

function T:test_document_is_served_without_its_own_route()
  local a = app { info = INFO, enabled = true }
  local response = get(a:boot(), "/openapi.json")
  self:assert_equal(200, response.status)
  self:assert_equal("application/json", response.fields:get("Content-Type"))
  local document = json.decode(response.content)
  self:assert_equal("Shop", document.info.title)
  self:assert_true(document.paths["/health"] ~= nil)
  self:assert_nil(document.paths["/openapi.json"])
  self:assert_equal(1, #a.entries)
end

function T:test_path_and_name_are_options_and_document_is_kept()
  local serve = app({ info = INFO, enabled = true, path = "/spec", name = "spec" }):boot()
  local first, second = get(serve, "/spec"), get(serve, "/spec")
  self:assert_equal(200, first.status)
  self:assert_equal(first.content, second.content)
  self:assert_equal(404, get(serve, "/openapi.json").status)
end

function T:test_not_served_without_the_option_or_when_disabled_or_outside_development()
  self:assert_equal(404, get(app(nil):boot(), "/openapi.json").status)
  self:assert_equal(404, get(app({ info = INFO, enabled = false }):boot(), "/openapi.json").status)
  -- no configuration: not in development, so not served by default
  self:assert_equal(404, get(app({ info = INFO }):boot(), "/openapi.json").status)
end

function T:test_invalid_option_is_refused()
  self:assert_error(function() app({}):boot() end)
  self:assert_error(function() app({ info = INFO, bogus = 1 }):boot() end)
  self:assert_error(function() app({ info = INFO, path = "" }):boot() end)
  self:assert_error(function() app("x"):boot() end)
end

function T:test_contract_is_exported_whether_or_not_it_is_served()
  local a = app { info = INFO, enabled = false }
  a:boot()
  local document = json.decode(a:contract())
  self:assert_equal("Shop", document.info.title)
  self:assert_true(document.paths["/health"] ~= nil)
  self:assert_nil(document.paths["/openapi.json"])
  self:assert_equal(a:contract(), a:contract(false))
  self:assert_true(#a:contract(true) > #a:contract(false))
end

function T:test_contract_needs_a_booted_application_and_the_option()
  self:assert_error(function() app({ info = INFO }):contract() end)
  local a = app(nil)
  a:boot()
  self:assert_error(function() a:contract() end)
end

return T
