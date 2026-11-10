---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local schema = require("hecate.schema")
local kernel = require("hecate.kernel")
local dispatcher = require("hecate.kernel.dispatcher")
local T = test.Case("InputTest")

local SECRET <const> = "s3cr3t-offending-value"

local function request(method, target, options)
  options = options or {}
  local fields = http.Fields(options.fields)
  if options.content ~= nil and options.type ~= false then fields:set("Content-Type", options.type or "application/json") end
  return http.Request({ method = method, target = target, fields = fields, content = options.content,
    content_stream = options.content_stream })
end

local function serve_with(method, path, spec, options)
  local module = kernel.routes("t")
  spec.action = spec.action or function(r) return { ok = true } end
  module[method:lower()](module, path, spec)
  local serve = dispatcher.build(module:routes(), options)
  return serve
end

local User = core.class("InputUser", nil, { implements = { schema.Representable } })
function User.schema()
  return schema.object({ name = schema.string(), age = schema.optional(schema.integer()) })
end
core.finalise(User)

function T:test_path_and_query_are_coerced_into_request_parameters()
  local seen
  local serve = serve_with("GET", "/users/{id}", {
    parameters = {
      path = { id = schema.integer({ minimum = 1 }) },
      query = { limit = schema.default(schema.integer(), 10), tags = schema.optional(schema.array(schema.string())),
        active = schema.optional(schema.boolean()) },
    },
    action = function(r) seen = r.parameters; return { ok = true } end,
  })
  local response = serve(request("GET", "/users/42?limit=5&tags=a,b&active=true&ignored=1"))
  self:assert_equal(200, response.status)
  self:assert_equal(42, seen.path.id)
  self:assert_equal(5, seen.query.limit)
  self:assert_equal("b", seen.query.tags[2])
  self:assert_equal(true, seen.query.active)
  self:assert_nil(seen.query.ignored)
  serve(request("GET", "/users/7"))
  self:assert_equal(10, seen.query.limit)
  serve(request("GET", "/users/7?tags=x&tags=y"))
  self:assert_equal(2, #seen.query.tags)
end

function T:test_header_fields_and_cookies_are_coerced()
  local seen
  local serve = serve_with("GET", "/x", {
    parameters = { fields = { ["X-Page"] = schema.integer() }, cookies = { session = schema.string() } },
    action = function(r) seen = r.parameters; return nil end,
  })
  local response = serve(request("GET", "/x", { fields = { ["x-page"] = "3", Cookie = "session=abc" } }))
  self:assert_equal(200, response.status)
  self:assert_equal(3, seen.fields["X-Page"])
  self:assert_equal("abc", seen.cookies.session)
end

function T:test_a_parameter_violation_is_a_422_that_points_at_the_location_and_echoes_nothing()
  local ran = false
  local serve = serve_with("GET", "/users/{id}", {
    parameters = { path = { id = schema.integer() }, query = { limit = schema.integer({ maximum = 100 }) } },
    action = function() ran = true end,
  })
  local range = serve(request("GET", "/users/1?limit=500"))
  self:assert_equal(422, range.status)
  self:assert_equal("/query/limit", json.decode(range.content).errors[1].pointer)
  self:assert_equal("maximum", json.decode(range.content).errors[1].code)
  local response = serve(request("GET", "/users/" .. SECRET .. "?limit=500"))
  self:assert_equal(422, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_false(ran)
  self:assert_nil(string.find(response.content, SECRET, 1, true))
  local body = json.decode(response.content)
  local pointers = {}
  for _, entry in ipairs(body.errors) do pointers[entry.pointer] = entry.code; self:assert_nil(entry.message) end
  self:assert_equal("coercion", pointers["/path/id"])
  -- With expose_details the messages are there, still without the value.
  local exposed = serve_with("GET", "/users/{id}", { parameters = { path = { id = schema.integer() } } },
    { expose_details = true })(request("GET", "/users/" .. SECRET))
  self:assert_equal(422, exposed.status)
  self:assert_nil(string.find(exposed.content, SECRET, 1, true))
  self:assert_equal("string", type(json.decode(exposed.content).errors[1].message))
end

function T:test_a_missing_required_query_parameter_and_a_bad_percent_encoding()
  local serve = serve_with("GET", "/x", { parameters = { query = { q = schema.string() } } })
  self:assert_equal(422, serve(request("GET", "/x")).status)
  self:assert_equal(400, serve(request("GET", "/x?q=%zz")).status)
  self:assert_equal(200, serve(request("GET", "/x?q=a+b")).status)
end

function T:test_json_content_is_built_with_a_class_bound_schema_and_consumed()
  local seen, after
  local serve = serve_with("POST", "/users", {
    content = { ["application/json"] = schema.of(User) },
    action = function(r)
      seen = r.content
      after = select(2, pcall(r.read_content, r))
      return nil
    end,
  })
  local response = serve(request("POST", "/users", { content = '{"name":"Ada","age":36}' }))
  self:assert_equal(200, response.status)
  self:assert_true(core.is_instance_of(seen, User))
  self:assert_equal("Ada", seen.name)
  self:assert_equal(36, seen.age)
  self:assert_true(core.is_instance_of(after, http.ContentError))
  self:assert_equal("consumed", after.context.reason)
  -- A media type with parameters is accepted (RFC 9110 section 8.3.1).
  local with_charset = serve(request("POST", "/users", { content = '{"name":"Ada"}', type = "application/json; charset=utf-8" }))
  self:assert_equal(200, with_charset.status)
end

function T:test_content_with_a_plain_schema_is_validated_and_defaults_apply()
  local seen
  local serve = serve_with("POST", "/items", {
    content = { ["application/json"] = schema.object({ qty = schema.default(schema.integer(), 1), name = schema.string() }) },
    action = function(r) seen = r.content end,
  })
  self:assert_equal(200, serve(request("POST", "/items", { content = '{"name":"n"}' })).status)
  self:assert_equal(1, seen.qty)
  local bad = serve(request("POST", "/items", { content = '{"name":5,"extra":"' .. SECRET .. '"}' }))
  self:assert_equal(422, bad.status)
  self:assert_nil(string.find(bad.content, SECRET, 1, true))
  local pointers = {}
  for _, entry in ipairs(json.decode(bad.content).errors) do pointers[entry.pointer] = entry.code end
  self:assert_equal("type", pointers["/name"])
  self:assert_equal("additional_properties", pointers["/extra"])
end

function T:test_patch_relaxes_the_required_properties_of_the_content()
  local seen
  local serve = serve_with("PATCH", "/users/{id}", {
    parameters = { path = { id = schema.integer() } },
    content = { ["application/json"] = schema.of(User) },
    action = function(r) seen = r.content end,
  })
  self:assert_equal(200, serve(request("PATCH", "/users/1", { content = '{"age":4}' })).status)
  self:assert_equal(4, seen.age)
  self:assert_equal(422, serve(request("PATCH", "/users/1", { content = '{"age":"x"}' })).status)
end

function T:test_malformed_json_is_a_400_and_a_wrong_media_type_a_415_without_echoing_input()
  local serve = serve_with("POST", "/x", { content = { ["application/json"] = schema.any() } })
  local malformed = serve(request("POST", "/x", { content = '{"a": ' .. SECRET }))
  self:assert_equal(400, malformed.status)
  self:assert_nil(string.find(malformed.content, SECRET, 1, true))
  self:assert_equal(415, serve(request("POST", "/x", { content = "{}", type = "text/plain" })).status)
  self:assert_equal(415, serve(request("POST", "/x", { content = "{}", type = false })).status)
  local deep = serve(request("POST", "/x", { content = string.rep("[", json.DEFAULT_MAX_DEPTH + 5) .. string.rep("]", json.DEFAULT_MAX_DEPTH + 5) }))
  self:assert_equal(400, deep.status)
end

function T:test_missing_content_is_decided_by_the_schema()
  local required = serve_with("POST", "/r", { content = { ["application/json"] = schema.of(User) } })
  self:assert_equal(422, required(request("POST", "/r")).status)
  local seen = "unset"
  local optional = serve_with("POST", "/o", {
    content = { ["application/json"] = schema.default(schema.of(User), { name = "anon" }) },
    action = function(r) seen = r.content end,
  })
  self:assert_equal(200, optional(request("POST", "/o")).status)
  self:assert_equal("anon", seen.name)
end

function T:test_content_over_the_limit_is_a_413()
  local serve = serve_with("POST", "/x", { content = { ["application/json"] = schema.any() } })
  local stream = http.ContentStream(coroutine.wrap(function() coroutine.yield(string.rep("a", 50)) end), { limit = 10 })
  local response = serve(request("POST", "/x", { content = "", content_stream = stream, fields = { ["Content-Type"] = "application/json" } }))
  self:assert_equal(413, response.status)
end

function T:test_a_route_without_content_keeps_the_stream_untouched()
  local text
  local serve = serve_with("POST", "/raw", { action = function(r) text = r:read_content(); return nil end })
  self:assert_equal(200, serve(request("POST", "/raw", { content = "raw bytes", type = "text/plain" })).status)
  self:assert_equal("raw bytes", text)
end

function T:test_filters_run_before_the_inputs_are_read()
  local reads = 0
  local stream = http.ContentStream(function() reads = reads + 1; return nil end)
  local deny = { handle = function() return kernel.problems.response(403) end }
  local serve = serve_with("POST", "/x", { filters = { deny }, content = { ["application/json"] = schema.any() } })
  local response = serve(request("POST", "/x", { content = "", content_stream = stream, fields = { ["Content-Type"] = "application/json" } }))
  self:assert_equal(403, response.status)
  self:assert_equal(0, reads)
end

function T:test_a_validation_error_raised_by_the_action_stays_a_500()
  local serve = serve_with("GET", "/x", {
    parameters = { query = { q = schema.optional(schema.string()) } },
    action = function() schema.integer():check("nope") end,
  })
  self:assert_equal(500, serve(request("GET", "/x?q=a")).status)
end

function T:test_content_declared_only_for_another_media_type_is_refused_at_build()
  local err = self:assert_error(function()
    serve_with("POST", "/x", { content = { ["application/xml"] = schema.any() } })
  end)
  self:assert_equal("unsupported_content_type", err.context.reason)
end

function T:test_a_route_without_inputs_gets_no_step()
  local input = require("hecate.kernel.input")
  local entry = kernel.route.normalise({ method = "GET", path = "/plain", action = function() end }, { origin = "t" })
  self:assert_nil(input.compile(entry))
end
return T
