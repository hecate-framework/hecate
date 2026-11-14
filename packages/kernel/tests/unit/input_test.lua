---@diagnostic disable: undefined-field, param-type-mismatch
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
  }, { inputs = "lax" })
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

function T:test_a_repeated_content_type_field_is_a_400()
  local ran = false
  local serve = serve_with("POST", "/x", {
    content = { ["application/json"] = schema.object({ a = schema.optional(schema.integer()) }) },
    action = function() ran = true; return nil end,
  })
  local req = request("POST", "/x", { content = "{}" })
  req.fields:add("Content-Type", "text/plain")
  local response = serve(req)
  self:assert_equal(400, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_false(ran)
  -- A single field still passes.
  self:assert_equal(200, serve(request("POST", "/x", { content = "{}" })).status)
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
  local first = json.decode(range.content).errors[1]
  self:assert_equal("/limit", first.pointer)
  self:assert_equal("query", first.source)
  self:assert_equal("maximum", first.code)
  local response = serve(request("GET", "/users/" .. SECRET .. "?limit=500"))
  self:assert_equal(422, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_false(ran)
  self:assert_nil(string.find(response.content, SECRET, 1, true))
  local body = json.decode(response.content)
  local pointers = {}
  for _, entry in ipairs(body.errors) do pointers[entry.source .. entry.pointer] = entry.code; self:assert_nil(entry.message) end
  self:assert_equal("coercion", pointers["path/id"])
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
  for _, entry in ipairs(json.decode(bad.content).errors) do self:assert_equal("content", entry.source) end
end

local function sources_of(response)
  local found = {}
  for _, entry in ipairs(json.decode(response.content).errors) do found[entry.source] = entry end
  return found
end

function T:test_every_entry_of_a_422_names_its_source_with_a_pointer_relative_to_the_value()
  local serve = serve_with("POST", "/s/{id}", {
    parameters = {
      path = { id = schema.integer() }, query = { q = schema.integer() },
      fields = { ["X-Page"] = schema.integer() }, cookies = { session = schema.integer() },
    },
    content = { ["application/json"] = schema.object({ name = schema.string() }) },
  })
  local response = serve(request("POST", "/s/x?q=y", { content = '{"name":1}',
    fields = { ["X-Page"] = "z", Cookie = "session=w" } }))
  self:assert_equal(422, response.status)
  local found = sources_of(response)
  self:assert_equal("/id", found.path.pointer)
  self:assert_equal("/q", found.query.pointer)
  self:assert_equal("/X-Page", found.header.pointer)
  self:assert_equal("/session", found.cookie.pointer)
  self:assert_nil(found.fields)
  -- Parameters and content are read in turn: the content of this one is refused on its own.
  local content = serve(request("POST", "/s/1?q=2", { content = '{"name":1}', fields = { ["X-Page"] = "3", Cookie = "session=4" } }))
  self:assert_equal("/name", sources_of(content).content.pointer)
end

function T:test_expose_details_keeps_the_message_with_the_source()
  local serve = serve_with("GET", "/x", { parameters = { query = { q = schema.integer() } } }, { expose_details = true })
  local entry = json.decode(serve(request("GET", "/x?q=" .. SECRET)).content).errors[1]
  self:assert_equal("query", entry.source)
  self:assert_equal("string", type(entry.message))
end

function T:test_strict_inputs_refuse_undeclared_query_parameters_by_name_and_never_echo_the_value()
  local ran = false
  local serve = serve_with("GET", "/x", {
    parameters = { query = { limit = schema.optional(schema.integer()) } },
    action = function() ran = true end,
  })
  local response = serve(request("GET", "/x?limit=1&zeta=" .. SECRET .. "&a%2Fb~c=1&zeta=2&alpha"))
  self:assert_equal(422, response.status)
  self:assert_false(ran)
  self:assert_nil(string.find(response.content, SECRET, 1, true))
  local errors = json.decode(response.content).errors
  local pointers = {}
  for _, entry in ipairs(errors) do
    self:assert_equal("query", entry.source)
    self:assert_equal("additional_properties", entry.code)
    self:assert_nil(entry.message)
    pointers[#pointers + 1] = entry.pointer
  end
  self:assert_equal("/zeta,/a~1b~0c,/alpha", table.concat(pointers, ","))
  self:assert_equal(200, serve(request("GET", "/x?limit=1")).status)
  self:assert_equal(200, serve(request("GET", "/x")).status)
  local exposed = serve_with("GET", "/x", {}, { expose_details = true })(request("GET", "/x?zeta=1"))
  self:assert_equal("string", type(json.decode(exposed.content).errors[1].message))
end

function T:test_strict_is_the_default_and_applies_to_a_route_that_declares_no_query()
  local serve = serve_with("GET", "/plain", { parameters = { fields = { ["X-Page"] = schema.optional(schema.integer()) } } })
  self:assert_equal(422, serve(request("GET", "/plain?page=2")).status)
  local bare = serve_with("GET", "/bare", {})
  self:assert_equal(422, bare(request("GET", "/bare?page=2")).status)
  self:assert_equal(200, bare(request("GET", "/bare")).status)
  self:assert_equal(200, bare(request("GET", "/bare?")).status)
end

function T:test_strict_applies_to_a_route_that_declares_only_content()
  local ran = false
  local spec = {
    content = { ["application/json"] = schema.object({ x = schema.integer() }) },
    action = function() ran = true; return { ok = true } end,
  }
  local serve = serve_with("POST", "/only-content", spec)
  local response = serve(request("POST", "/only-content?undeclared=1", { content = '{"x":1}' }))
  self:assert_equal(422, response.status)
  self:assert_false(ran)
  local entry = json.decode(response.content).errors[1]
  self:assert_equal("query", entry.source)
  self:assert_equal("/undeclared", entry.pointer)
  self:assert_equal(200, serve(request("POST", "/only-content", { content = '{"x":1}' })).status)
  local lax = serve_with("POST", "/only-content", spec, { inputs = "lax" })
  self:assert_equal(200, lax(request("POST", "/only-content?undeclared=1", { content = '{"x":1}' })).status)
end

function T:test_lax_inputs_drop_undeclared_query_parameters()
  local seen
  local serve = serve_with("GET", "/x", {
    parameters = { query = { limit = schema.optional(schema.integer()) } },
    action = function(r) seen = r.parameters.query; return nil end,
  }, { inputs = "lax" })
  self:assert_equal(200, serve(request("GET", "/x?limit=3&other=1")).status)
  self:assert_equal(3, seen.limit)
  self:assert_nil(seen.other)
  self:assert_equal(200, serve_with("GET", "/bare", {}, { inputs = "lax" })(request("GET", "/bare?other=1")).status)
end

function T:test_undeclared_header_fields_and_cookies_are_always_dropped()
  for _, policy in ipairs({ "strict", "lax" }) do
    local seen
    local serve = serve_with("GET", "/x", {
      parameters = { fields = { ["X-Page"] = schema.integer() }, cookies = { session = schema.string() } },
      action = function(r) seen = r.parameters; return nil end,
    }, { inputs = policy })
    local response = serve(request("GET", "/x", { fields = { ["X-Page"] = "1", ["X-Other"] = "o", Cookie = "session=a; other=b" } }))
    self:assert_equal(200, response.status)
    self:assert_nil(seen.fields["X-Other"])
    self:assert_nil(seen.cookies.other)
  end
end

function T:test_the_undeclared_entries_are_capped()
  local problems = require("hecate.kernel.problems")
  local parts = {}
  for i = 1, problems.MAX_ERRORS + 20 do parts[i] = "p" .. i .. "=1" end
  local response = serve_with("GET", "/x", {})(request("GET", "/x?" .. table.concat(parts, "&")))
  self:assert_equal(422, response.status)
  self:assert_equal(problems.MAX_ERRORS, #json.decode(response.content).errors)
end

function T:test_an_unknown_inputs_policy_is_refused_at_build()
  local err = self:assert_error(function() serve_with("GET", "/x", {}, { inputs = "loose" }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
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

function T:test_an_optional_content_schema_accepts_an_absent_body()
  local seen = "unset"
  local optional = serve_with("POST", "/opt", {
    content = { ["application/json"] = schema.optional(schema.of(User)) },
    action = function(r) seen = r.content end,
  })
  self:assert_equal(200, optional(request("POST", "/opt")).status)
  self:assert_nil(seen)
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
local function recording_logger()
  local seen = {}
  return seen, { log = function(_, severity, message, fields) seen[#seen + 1] = { severity, message, fields } end }
end

function T:test_a_422_of_the_input_step_is_logged_as_a_warning_with_codes_and_never_values()
  local seen, logger = recording_logger()
  local serve = serve_with("GET", "/items", {
    parameters = { query = { limit = schema.integer({ minimum = 1 }) } },
  }, { logger = logger })
  self:assert_equal(422, serve(request("GET", "/items?limit=" .. SECRET)).status)
  self:assert_equal(1, #seen)
  self:assert_equal("warning", seen[1][1])
  self:assert_equal("request refused", seen[1][2])
  local fields = seen[1][3]
  self:assert_equal("GET", fields.method)
  self:assert_equal("/items", fields.path)
  self:assert_equal(422, fields.status)
  self:assert_equal("invalid_input", fields.reason)
  self:assert_equal(1, #fields.codes)
  self:assert_equal("string", type(fields.codes[1]))
  self:assert_nil(string.find(json.encode(fields), SECRET, 1, true))
end

function T:test_the_400_and_415_of_the_input_step_are_logged_without_the_content()
  local seen, logger = recording_logger()
  local serve = serve_with("POST", "/x", { content = { ["application/json"] = schema.object({ a = schema.integer() }) } },
    { logger = logger, inputs = "lax" })
  self:assert_equal(400, serve(request("POST", "/x?token=" .. SECRET, { content = '{"a": ' .. SECRET })).status)
  self:assert_equal(415, serve(request("POST", "/x", { content = "{}", type = "text/plain" })).status)
  self:assert_equal(2, #seen)
  self:assert_equal("malformed_content", seen[1][3].reason)
  self:assert_equal("/x", seen[1][3].path)
  self:assert_equal(415, seen[2][3].status)
  self:assert_equal("unsupported_media_type", seen[2][3].reason)
  for _, entry in ipairs(seen) do self:assert_equal("warning", entry[1]) end
  self:assert_nil(string.find(json.encode(seen), SECRET, 1, true))
end

function T:test_a_content_422_is_logged_with_its_codes()
  local seen, logger = recording_logger()
  local serve = serve_with("POST", "/x", { content = { ["application/json"] = schema.object({ name = schema.string() }) } },
    { logger = logger })
  self:assert_equal(422, serve(request("POST", "/x", { content = '{"name":7}' })).status)
  self:assert_equal(1, #seen)
  self:assert_equal(422, seen[1][3].status)
  self:assert_equal("string", type(seen[1][3].codes[1]))
end

function T:test_the_query_of_a_refused_request_is_never_logged()
  local seen, logger = recording_logger()
  local serve = serve_with("POST", "/orders/{id}", {
    parameters = { path = { id = schema.integer() } },
    content = { ["application/json"] = schema.object({ name = schema.string() }) },
  }, { logger = logger })
  self:assert_equal(422, serve(request("POST", "/orders/7?token=" .. SECRET, { content = '{"name":7}' })).status)
  self:assert_equal(1, #seen)
  self:assert_equal("/orders/7", seen[1][3].path)
  self:assert_nil(string.find(json.encode(seen), SECRET, 1, true))
end

function T:test_a_request_that_conforms_logs_nothing()
  local seen, logger = recording_logger()
  local serve = serve_with("GET", "/items", { parameters = { query = { limit = schema.integer() } } },
    { logger = logger })
  self:assert_equal(200, serve(request("GET", "/items?limit=3")).status)
  self:assert_equal(0, #seen)
end

return T
