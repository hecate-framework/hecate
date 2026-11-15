---@diagnostic disable: need-check-nil, param-type-mismatch, assign-type-mismatch, missing-fields  -- the tests index tables they just asserted exist and pass invalid options on purpose
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local openapi = require("hecate.openapi")
local T = test.Case("OpenApiBuildTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."

local INFO = { title = "Shop", version = "1.2.0" }

local function action() return nil end

local Id = schema.integer { minimum = 1 }
local User = schema.named("User", schema.object { id = Id, name = schema.string() })
local NewUser = schema.object { name = schema.string(), email = schema.optional(schema.string()) }

--- A problem class, as `hecate.kernel.problem` produces them: it implements `core.Problem` and carries the class
--- attributes `status` and `title` (the only ones read).
local function problem_class(name, attributes)
  local class = core.class(name, core.Error, { implements = { core.Problem } })
  for key, value in pairs(attributes) do class[key] = value end
  return core.finalise(class)
end

local NotFound = problem_class("NotFound", { status = 404, title = "Not Found", type = "about:blank" })

--- A route entry as `hecate.kernel.route.normalise` produces it, completed by `fields`.
local function entry(fields)
  local parameters = { path = {}, query = {}, fields = {}, cookies = {} }
  for location, map in pairs(fields.parameters or {}) do parameters[location] = map end
  local result = {
    method = "GET", path = "/", name = (fields.method or "GET") .. " " .. (fields.path or "/"), tags = {},
    deprecated = false, content = {}, responses = {}, security = {}, filters = {}, action = action, origin = "test",
  }
  for key, value in pairs(fields) do result[key] = value end
  result.parameters = parameters
  return result
end

local function routes()
  return {
    entry { method = "POST", path = "/users", name = "createUser", summary = "Create a user", tags = { "users" },
      content = { ["application/json"] = NewUser }, responses = { [201] = User, [422] = NotFound } },
    entry { method = "GET", path = "/users/{id}", name = "getUser", summary = "Fetch a user", description = "Fetch one.",
      tags = { "users" }, parameters = { path = { id = Id }, query = { verbose = schema.optional(schema.boolean()) },
        fields = { ["X-Trace"] = schema.optional(schema.string()) } },
      responses = { [200] = User, [404] = NotFound } },
    entry { method = "GET", path = "/users", name = "listUsers", tags = { "users" },
      parameters = { query = { page = schema.default(schema.integer(), 1), q = schema.string() } },
      responses = { [200] = schema.array(User) } },
    entry { method = "DELETE", path = "/users/{id}", name = "deleteUser", deprecated = true,
      parameters = { path = { id = Id } }, responses = { [204] = true, [404] = NotFound },
      security = { { bearer = {} } } },
    entry { method = "GET", path = "/files/{rest...}", name = "getFile",
      parameters = { path = { rest = schema.string() } }, responses = { [200] = true } },
  }
end

local function build(overrides)
  local options = { info = INFO, routes = routes() }
  for key, value in pairs(overrides or {}) do options[key] = value end
  return openapi.build(options)
end

local function raises_argument_error(case, fn, pattern)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  if pattern then case:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err)) end
  return err
end

function T:test_document_header_and_info()
  local document = openapi.build {
    info = { title = "Shop", version = "1.2.0", summary = "s", description = "d", terms_of_service = "https://x.test/tos",
      contact = { name = "Ops", url = "https://x.test", email = "ops@x.test" },
      license = { name = "MIT", identifier = "MIT" } },
    servers = { { url = "https://api.x.test", description = "production" }, { url = "http://localhost:8080" } },
    routes = {},
  }
  self:assert_equal("3.1.0", document.openapi)
  self:assert_equal("Shop", document.info.title)
  self:assert_equal("1.2.0", document.info.version)
  self:assert_equal("https://x.test/tos", document.info.termsOfService)
  self:assert_equal("ops@x.test", document.info.contact.email)
  self:assert_equal("MIT", document.info.license.identifier)
  self:assert_equal("production", document.servers[1].description)
  self:assert_equal("http://localhost:8080", document.servers[2].url)
end

function T:test_every_route_appears_with_its_operation()
  local document = build()
  local count = 0
  for _, item in pairs(document.paths) do for _ in pairs(item) do count = count + 1 end end
  self:assert_equal(5, count)
  self:assert_equal("createUser", document.paths["/users"].post.operationId)
  self:assert_equal("Fetch one.", document.paths["/users/{id}"].get.description)
  self:assert_true(document.paths["/users/{id}"].delete.deprecated)
  self:assert_nil(document.paths["/users/{id}"].get.deprecated)
  self:assert_not_nil(document.paths["/files/{rest}"].get, "a wildcard {rest...} is documented as {rest}")
  self:assert_equal("bearer", next(document.paths["/users/{id}"].delete.security[1]))
end

function T:test_security_scopes_are_json_arrays()
  -- OpenAPI 3.1 section 4.8.30: a Security Requirement Object maps a scheme name to an array of scopes, `[]` when none.
  local declared = { { bearer = {} }, { oauth = { "read", "write" }, key = {} } }
  local document = openapi.build { info = INFO, routes = { entry { method = "GET", path = "/s", name = "s", security = declared } } }
  local security = document.paths["/s"].get.security
  self:assert_true(json.is_array(security))
  self:assert_true(json.is_array(security[1].bearer))
  self:assert_true(json.is_array(security[2].key))
  self:assert_true(json.is_array(security[2].oauth))
  self:assert_equal("read,write", table.concat(security[2].oauth, ","))
  self:assert_false(json.is_array(declared[1].bearer), "the declared requirements are not modified")
  local text = openapi.encode(document)
  self:assert_true(text:find('"security":[{"bearer":[]},{"key":[],"oauth":["read","write"]}]', 1, true) ~= nil, text)
  local decoded = json.decode(text)
  self:assert_true(json.is_array(decoded.paths["/s"].get.security[1].bearer))
  self:assert_equal(0, #openapi.diff(document, decoded))
end

function T:test_invalid_security_is_refused()
  for _, security in ipairs({ "x", { "bearer" }, { { bearer = "read" } }, { { bearer = { 1 } } }, { { [1] = {} } } }) do
    raises_argument_error(self, function()
      openapi.build { info = INFO, routes = { entry { method = "GET", path = "/s", name = "s", security = security } } }
    end, "security")
  end
end

function T:test_no_empty_list_is_encoded_as_an_object()
  local document = openapi.build { info = INFO, servers = {}, tags = {}, routes = {
    entry { method = "GET", path = "/e", name = "e", tags = {}, security = {}, responses = { [200] = schema.object {} } },
    entry { method = "GET", path = "/enum", name = "enum", responses = { [200] = schema.array(schema.object {}) } } } }
  for _, list in ipairs({ "servers", "tags" }) do self:assert_nil(document[list], list .. " is omitted when empty") end
  local get = document.paths["/e"].get
  for _, list in ipairs({ "tags", "security", "parameters" }) do self:assert_nil(get[list], list .. " is omitted when empty") end
  -- the generated schemas: every empty list keyword must be marked (`required`, `enum`, `allOf`, ...)
  local text = openapi.encode(document)
  for _, keyword in ipairs({ "required", "enum", "allOf", "anyOf", "oneOf", "prefixItems", "examples" }) do
    self:assert_nil(text:find('"' .. keyword .. '":{}', 1, true), keyword .. " encoded as {}")
  end
end

function T:test_a_route_without_declared_responses_still_appears_with_a_default_response()
  local document = openapi.build { info = INFO, routes = { entry { method = "GET", path = "/x" } } }
  self:assert_not_nil(document.paths["/x"].get.responses.default.description)
end

function T:test_parameters_are_ordered_and_required_follows_the_schema()
  local get = build().paths["/users"].get
  self:assert_equal("page", get.parameters[1].name)
  self:assert_false(get.parameters[1].required)
  self:assert_equal("query", get.parameters[1]["in"])
  self:assert_equal(1, get.parameters[1].schema.default)
  self:assert_equal("q", get.parameters[2].name)
  self:assert_true(get.parameters[2].required)
  local one = build().paths["/users/{id}"].get.parameters
  self:assert_equal("path", one[1]["in"])
  self:assert_true(one[1].required)
  self:assert_equal("query", one[2]["in"])
  self:assert_equal("header", one[3]["in"])
  self:assert_equal("X-Trace", one[3].name)
  self:assert_false(one[3].required)
  self:assert_nil(one[1].schema["$schema"])
end

function T:test_request_body_and_responses()
  local post = build().paths["/users"].post
  self:assert_true(post.requestBody.required)
  self:assert_equal("string", post.requestBody.content["application/json"].schema.properties.name.type)
  self:assert_equal("#/components/schemas/User", post.responses["201"].content["application/json"].schema["$ref"])
  local delete = build().paths["/users/{id}"].delete
  self:assert_equal("No Content", delete.responses["204"].description)
  self:assert_nil(delete.responses["204"].content)
end

function T:test_defs_become_components_schemas()
  local document = build()
  local text = json.encode(document)
  self:assert_nil(text:find("#/$defs/", 1, true), "no reference to $defs remains")
  self:assert_equal("object", document.components.schemas.User.type)
  self:assert_nil(document.components.schemas.User["$schema"])
  local list = document.paths["/users"].get.responses["200"].content["application/json"].schema
  self:assert_equal("#/components/schemas/User", list.items["$ref"])
end

function T:test_problem_details_component_is_referenced_by_error_responses()
  local document = build()
  local problem = document.components.schemas.ProblemDetails
  self:assert_equal("object", problem.type)
  self:assert_equal("integer", problem.properties.status.type)
  self:assert_equal("uri-reference", problem.properties.type.format)
  local response = document.paths["/users/{id}"].get.responses["404"]
  self:assert_equal("Not Found", response.description)
  self:assert_equal("#/components/schemas/ProblemDetails", response.content["application/problem+json"].schema["$ref"])
  self:assert_nil(response.content["application/json"])
end

function T:test_ref_rewriting_leaves_constants_alone()
  local Tagged = schema.named("Tagged", schema.object { kind = schema.literal("#/$defs/User"), ref = schema.string() })
  local document = openapi.build { info = INFO, routes = { entry { path = "/t", responses = { [200] = Tagged } } } }
  self:assert_equal("#/$defs/User", document.components.schemas.Tagged.properties.kind.const)
end

function T:test_schema_name_collisions_are_refused()
  local A = schema.named("Thing", schema.object { a = schema.string() })
  local B = schema.named("Thing", schema.object { b = schema.string() })
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/a", responses = { [200] = A } },
      entry { path = "/b", responses = { [200] = B } } } }
  end, "Thing")
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/a", responses = { [200] = schema.named("ProblemDetails", schema.string()) } } } }
  end, "ProblemDetails")
  -- equal bodies are shared
  local C = schema.named("Thing", schema.object { a = schema.string() })
  openapi.build { info = INFO, routes = { entry { path = "/a", responses = { [200] = A } }, entry { path = "/b", responses = { [200] = C } } } }
end

function T:test_output_does_not_depend_on_the_order_of_the_routes()
  local forward = routes()
  local backward = {}
  for index = #forward, 1, -1 do backward[#backward + 1] = forward[index] end
  local first = openapi.encode(openapi.build { info = INFO, routes = forward })
  local second = openapi.encode(openapi.build { info = INFO, routes = backward })
  self:assert_equal(first, second)
  self:assert_equal(first, openapi.encode(build()))
end

function T:test_golden_document()
  local document = openapi.build {
    info = { title = "Shop", version = "1.2.0", contact = { name = "Ops" }, license = { name = "MIT", identifier = "MIT" } },
    servers = { { url = "https://api.x.test" } }, routes = routes(),
    tags = { { name = "users", description = "Accounts of the shop.", external_docs = { url = "https://x.test/users" } } },
    external_docs = { url = "https://x.test/docs", description = "The guide." },
  }
  local actual = openapi.encode(document, { pretty = true })
  local path = here .. "/../fixtures/shop.openapi.json"
  if os.getenv("HECATE_UPDATE_GOLDEN") then
    local file = assert(io.open(path, "wb"))
    file:write(actual, "\n")
    file:close()
  end
  local file = assert(io.open(path, "rb"), "missing golden file " .. path)
  local expected = file:read("a")
  file:close()
  self:assert_equal(expected, actual .. "\n")
end

function T:test_tags_are_collected_sorted()
  local document = build()
  self:assert_equal("users", document.tags[1].name)
  self:assert_equal(1, #document.tags)
end

function T:test_listed_tags_keep_their_order_and_unlisted_ones_follow_alphabetically()
  local list = {
    entry { path = "/a", name = "a", tags = { "zeta", "users" } },
    entry { path = "/b", name = "b", tags = { "alpha", "orders" } },
  }
  local document = openapi.build { info = INFO, routes = list, tags = {
    { name = "users", description = "Accounts", external_docs = { url = "https://x.test/users", description = "More" } },
    { name = "orders" }, { name = "unused" },
  } }
  local names = {}
  for index, tag in ipairs(document.tags) do names[index] = tag.name end
  self:assert_equal("users,orders,unused,alpha,zeta", table.concat(names, ","))
  self:assert_equal("Accounts", document.tags[1].description)
  self:assert_equal("https://x.test/users", document.tags[1].externalDocs.url)
  self:assert_equal("More", document.tags[1].externalDocs.description)
  self:assert_nil(document.tags[2].description)
  self:assert_nil(document.tags[4].description)
end

function T:test_invalid_tags_are_refused()
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = { { name = "a" }, { name = "a" } } } end, "duplicate")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = { { name = 1 } } } end, "tags[1].name")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = { {} } } end, "tags[1].name")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = { { name = "a", nonsense = 1 } } } end, "nonsense")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = { { name = "a", external_docs = {} } } } end, "url")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, tags = "x" } end, "tags")
end

function T:test_external_docs()
  local document = openapi.build { info = INFO, routes = {}, external_docs = { url = "https://x.test/docs", description = "Guide" } }
  self:assert_equal("https://x.test/docs", document.externalDocs.url)
  self:assert_equal("Guide", document.externalDocs.description)
  self:assert_nil(openapi.build { info = INFO, routes = {} }.externalDocs)
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, external_docs = { description = "x" } } end, "external_docs.url")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, external_docs = { url = "u", nonsense = 1 } } end, "nonsense")
end

function T:test_a_route_without_a_name_is_refused()
  raises_argument_error(self, function() openapi.build { info = INFO, routes = { entry { path = "/a", name = false } } } end, "routes[1].name")
  local nameless = entry { path = "/a" }
  nameless.name = nil
  raises_argument_error(self, function() openapi.build { info = INFO, routes = { nameless } } end, "routes[1].name")
  local empty = entry { path = "/a" }
  empty.name = ""
  raises_argument_error(self, function() openapi.build { info = INFO, routes = { empty } } end, "routes[1].name")
end

function T:test_request_body_required_follows_content_optional()
  local function body(optional)
    local fields = { method = "POST", path = "/x", name = "x", content = { ["application/json"] = NewUser } }
    if optional ~= nil then fields.content_optional = optional end
    return openapi.build { info = INFO, routes = { entry(fields) } }.paths["/x"].post.requestBody
  end
  self:assert_true(body(nil).required)
  self:assert_true(body(false).required)
  self:assert_false(body(true).required)
end

function T:test_a_wildcard_is_documented_without_its_ellipsis()
  local document = build()
  self:assert_not_nil(document.paths["/files/{rest}"])
  self:assert_nil(document.paths["/files/{rest...}"])
  self:assert_equal("getFile", document.paths["/files/{rest}"].get.operationId)
end

function T:test_a_response_without_a_phrase_falls_back_to_the_class_label()
  local document = openapi.build { info = INFO, routes = { entry { path = "/x", name = "x",
    responses = { [299] = true, [499] = true, [599] = true, [199] = true, [399] = true, [418] = true } } } }
  local responses = document.paths["/x"].get.responses
  self:assert_equal("Success", responses["299"].description)
  self:assert_equal("Client Error", responses["499"].description)
  self:assert_equal("Server Error", responses["599"].description)
  self:assert_equal("Informational", responses["199"].description)
  self:assert_equal("Redirection", responses["399"].description)
  self:assert_equal("I'm a teapot", responses["418"].description)
end

function T:test_a_problem_is_recognised_by_the_interface_not_by_its_shape()
  -- a plain table with `status` and `title` is no problem class, and no schema either: refused
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/x", name = "x", responses = { [404] = { status = 404, title = "Not Found" } } } } }
  end, "route \"x\"")
  -- a class that does not implement core.Problem is no problem class
  local PlainClass = core.class("Plain", core.Error)
  PlainClass.status, PlainClass.title = 404, "Not Found"
  local Plain = core.finalise(PlainClass)
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/x", name = "x", responses = { [404] = Plain } } } }
  end, "route \"x\"")
  -- a subclass inherits the declaration
  local Child = core.finalise(core.class("ChildProblem", NotFound))
  local document = openapi.build { info = INFO, routes = { entry { path = "/x", name = "x", responses = { [404] = Child } } } }
  self:assert_equal("Not Found", document.paths["/x"].get.responses["404"].description)
end

function T:test_problem_attributes_are_validated()
  local function refuses(attributes)
    local class = problem_class("Bad" .. tostring(attributes.status), attributes)
    local err = raises_argument_error(self, function()
      openapi.build { info = INFO, routes = { entry { path = "/x", name = "createX", responses = { [400] = class } } } }
    end, "createX")
    self:assert_true(tostring(err):find("400", 1, true) ~= nil, tostring(err))
    return err
  end
  refuses({ status = 200, title = "Fine" })
  refuses({ status = 404.5, title = "Fractional" })
  refuses({ status = "404", title = "Text" })
  refuses({ status = 404, title = 7 })
  local err = refuses({ status = 600, title = "Out of range secret-value" })
  self:assert_nil(tostring(err):find("secret-value", 1, true), "no user data in the message")
  -- an empty title is accepted
  local ok = problem_class("EmptyTitle", { status = 409, title = "" })
  local document = openapi.build { info = INFO, routes = { entry { path = "/x", name = "x", responses = { [409] = ok } } } }
  self:assert_equal("", document.paths["/x"].get.responses["409"].description)
end

function T:test_invalid_options_are_refused()
  raises_argument_error(self, function() openapi.build {} end, "info")
  raises_argument_error(self, function() openapi.build { info = { title = "x" }, routes = {} } end, "version")
  raises_argument_error(self, function() openapi.build { info = INFO } end, "routes")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, nonsense = 1 } end, "nonsense")
  raises_argument_error(self, function() openapi.build { info = INFO, routes = {}, servers = { {} } } end, "url")
  raises_argument_error(self, function()
    openapi.build { info = { title = "x", version = "1", license = { name = "MIT", identifier = "MIT", url = "https://x" } }, routes = {} }
  end, "license")
end

function T:test_duplicate_operations_are_refused()
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/a", name = "one" }, entry { path = "/a", name = "two" } } }
  end, "GET /a")
  raises_argument_error(self, function()
    openapi.build { info = INFO, routes = { entry { path = "/a", name = "same" }, entry { path = "/b", name = "same" } } }
  end, "same")
end

function T:test_routes_are_not_modified()
  local list = routes()
  local before = json.encode(openapi.build { info = INFO, routes = list })
  self:assert_equal(before, json.encode(openapi.build { info = INFO, routes = list }))
  self:assert_equal(5, #list)
end

return T
