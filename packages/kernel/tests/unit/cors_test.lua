---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
-- The shipped CORS filter (OQ-136): configuration keys, preflight, credentials, refused combinations.
local test = require("harness.test")
local http = require("hecate.http")
local core = require("hecate.core")
local kernel = require("hecate.kernel")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../../../config/tests/support/fixture.lua")
local T = test.Case("CorsTest")

local APP = "https://app.example.com"

local function application(cors, extra)
  local routes = kernel.routes("items")
  routes:get("/items", { name = "items.list", action = function() return { ok = true } end })
  local options = { routes = { routes }, cors = cors }
  for key, value in pairs(extra or {}) do options[key] = value end
  return kernel.Application(options):boot()
end

local function ask(serve, method, fields, target)
  return serve(http.Request({ method = method, target = target or "/items", fields = http.Fields(fields or {}) }))
end

function T:test_nothing_is_added_without_the_option()
  local serve = application(nil)
  local response = ask(serve, "GET", { Origin = APP })
  self:assert_equal(200, response.status)
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
  self:assert_nil(response.fields:get("Vary"))
end

function T:test_nothing_is_added_when_disabled()
  local serve = application({ enabled = false, allowed_origins = { APP } })
  self:assert_nil(ask(serve, "GET", { Origin = APP }).fields:get("Access-Control-Allow-Origin"))
end

function T:test_an_allowed_origin_is_echoed_and_the_response_varies_on_origin()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "GET", { Origin = APP })
  self:assert_equal(200, response.status)
  self:assert_equal(APP, response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("Origin", response.fields:get("Vary"))
  self:assert_nil(response.fields:get("Access-Control-Allow-Credentials"))
end

function T:test_a_refused_origin_gets_no_cors_header_but_still_varies()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "GET", { Origin = "https://evil.example" })
  self:assert_equal(200, response.status)
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("Origin", response.fields:get("Vary"))
end

function T:test_a_request_without_origin_is_untouched_but_varies()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "GET")
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("Origin", response.fields:get("Vary"))
end

function T:test_the_wildcard_answers_star_and_does_not_vary()
  local serve = application({ enabled = true, allowed_origins = { "*" } })
  local response = ask(serve, "GET", { Origin = APP })
  self:assert_equal("*", response.fields:get("Access-Control-Allow-Origin"))
  self:assert_nil(response.fields:get("Vary"))
end

function T:test_credentials_are_announced_for_an_allowed_origin()
  local serve = application({ enabled = true, allowed_origins = { APP }, allow_credentials = true })
  local response = ask(serve, "GET", { Origin = APP })
  self:assert_equal("true", response.fields:get("Access-Control-Allow-Credentials"))
end

function T:test_exposed_headers_are_listed()
  local serve = application({ enabled = true, allowed_origins = { APP }, exposed_headers = { "ETag", "X-Total" } })
  self:assert_equal("ETag, X-Total", ask(serve, "GET", { Origin = APP }).fields:get("Access-Control-Expose-Headers"))
end

function T:test_a_preflight_is_answered_without_a_route()
  local serve = application({
    enabled = true, allowed_origins = { APP }, allowed_methods = { "GET", "POST" },
    allowed_headers = { "Authorization", "Content-Type" }, max_age = 120,
  })
  local response = ask(serve, "OPTIONS", {
    Origin = APP, ["Access-Control-Request-Method"] = "POST", ["Access-Control-Request-Headers"] = "authorization, content-type",
  }, "/nowhere")
  self:assert_equal(204, response.status)
  self:assert_equal(APP, response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("GET, POST", response.fields:get("Access-Control-Allow-Methods"))
  self:assert_equal("Authorization, Content-Type", response.fields:get("Access-Control-Allow-Headers"))
  self:assert_equal("120", response.fields:get("Access-Control-Max-Age"))
  self:assert_equal("Origin", response.fields:get("Vary"))
end

function T:test_a_preflight_for_a_method_not_allowed_carries_no_permission()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "OPTIONS", { Origin = APP, ["Access-Control-Request-Method"] = "DELETE" })
  self:assert_equal(204, response.status)
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
  self:assert_nil(response.fields:get("Access-Control-Allow-Methods"))
end

function T:test_a_preflight_asking_for_a_header_not_allowed_carries_no_permission()
  local serve = application({ enabled = true, allowed_origins = { APP }, allowed_headers = { "Authorization" } })
  local response = ask(serve, "OPTIONS", {
    Origin = APP, ["Access-Control-Request-Method"] = "GET", ["Access-Control-Request-Headers"] = "X-Secret",
  })
  self:assert_equal(204, response.status)
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
end

function T:test_a_preflight_from_a_refused_origin_reaches_the_router()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "OPTIONS", { Origin = "https://evil.example", ["Access-Control-Request-Method"] = "GET" })
  self:assert_nil(response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("Origin", response.fields:get("Vary"))
end

function T:test_an_options_request_without_the_preflight_header_reaches_the_router()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "OPTIONS", { Origin = APP })
  self:assert_equal(APP, response.fields:get("Access-Control-Allow-Origin"))
  self:assert_nil(response.fields:get("Access-Control-Allow-Methods"), "not a preflight: routed as usual")
end

function T:test_the_cors_filter_is_outermost_so_it_marks_an_error_answer()
  local serve = application({ enabled = true, allowed_origins = { APP } })
  local response = ask(serve, "GET", { Origin = APP }, "/nowhere")
  self:assert_equal(404, response.status)
  self:assert_equal(APP, response.fields:get("Access-Control-Allow-Origin"))
end

function T:test_refused_combinations_fail_at_boot_with_the_key_named()
  local function refused(cors, key)
    local ok, err = pcall(application, cors)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_equal(key, err.context.key)
  end
  refused({ enabled = true, allowed_origins = { "*" }, allow_credentials = true }, "cors.allow_credentials")
  refused({ enabled = true, allowed_origins = { "*", APP } }, "cors.allowed_origins")
  refused({ enabled = true, allowed_origins = {} }, "cors.allowed_origins")
  refused({ enabled = true, allowed_origins = { "app.example.com" } }, "cors.allowed_origins")
  refused({ enabled = true, allowed_origins = { APP .. "/" } }, "cors.allowed_origins")
  refused({ enabled = true, allowed_origins = { APP }, max_age = -1 }, "cors.max_age")
  refused({ enabled = true, allowed_origins = { APP }, allowed_methods = { "get post" } }, "cors.allowed_methods")
  refused({ enabled = true, allowed_origins = { APP }, bogus = 1 }, "cors.bogus")
end

function T:test_a_disabled_filter_is_not_validated()
  application({ enabled = false, allowed_origins = { "*" }, allow_credentials = true })
end

function T:test_keys_come_from_the_configuration_and_the_option_overrides_them()
  local configuration = fixture.load({ env = {
    HECATE_CORS__ENABLED = "true",
    HECATE_CORS__ALLOWED_ORIGINS = APP .. ",https://admin.example.com",
    HECATE_CORS__ALLOW_CREDENTIALS = "true",
    HECATE_CORS__MAX_AGE = "30",
  } })
  local serve = application(nil, { configuration = configuration })
  local response = ask(serve, "GET", { Origin = "https://admin.example.com" })
  self:assert_equal("https://admin.example.com", response.fields:get("Access-Control-Allow-Origin"))
  self:assert_equal("true", response.fields:get("Access-Control-Allow-Credentials"))
  local overridden = application({ allowed_origins = { APP } }, { configuration = configuration })
  self:assert_nil(ask(overridden, "GET", { Origin = "https://admin.example.com" }).fields:get("Access-Control-Allow-Origin"))
  self:assert_equal(APP, ask(overridden, "GET", { Origin = APP }).fields:get("Access-Control-Allow-Origin"))
end

function T:test_the_filter_runs_before_the_global_filters_of_the_application()
  local seen
  local probe = { handle = function(_, request, next) seen = request.method; return next(request) end }
  local serve = application({ enabled = true, allowed_origins = { APP }, allowed_methods = { "GET" } }, { filters = { probe } })
  ask(serve, "OPTIONS", { Origin = APP, ["Access-Control-Request-Method"] = "GET" })
  self:assert_nil(seen, "the preflight is answered before the other filters")
end

return T
