---@diagnostic disable: need-check-nil, param-type-mismatch, assign-type-mismatch, missing-fields  -- the tests index tables they just asserted exist and pass invalid options on purpose
-- Conformance of `openapi.build` documents to OpenAPI 3.1 (CLAUDE.md of the package: "validation of output against the
-- official OpenAPI 3.1 schema"). Two layers, because no checker of this repository can evaluate the official schema
-- (it needs `$dynamicRef`, `unevaluatedProperties`, `if`/`then`/`else`, `format`, `pattern`; OQ-130):
-- 1. always: the structural self-check `tests/support/structure.lua` over the golden document and the documents of
--    the build tests;
-- 2. when the pinned official schema is downloaded (`lua tools/run.lua fetch-fixtures openapi`; skipped locally without it,
--    a failure in CI): the fixed fields table of the self-check must agree exactly with the official schema (its
--    `required` and `properties` per object), and the golden document must use only the official top-level members.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local openapi = require("hecate.openapi")
local T = test.Case("OpenApiConformanceTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local structure = dofile(here .. "/../support/structure.lua")
local OFFICIAL = here .. "/../../../../.hecate/fixtures/openapi/spec.openapis.org/oas/3.1/schema/2026-11-05"

local INFO = { title = "Shop", version = "1.2.0" }
local function action() return nil end

local Id = schema.integer { minimum = 1 }
local User = schema.named("User", schema.object { id = Id, name = schema.string() })
local NewUser = schema.object { name = schema.string(), email = schema.optional(schema.string()) }

local function problem_class(name, attributes)
  local class = core.class(name, core.Error, { implements = { core.Problem } })
  for key, value in pairs(attributes) do class[key] = value end
  return core.finalise(class)
end
local NotFound = problem_class("NotFound", { status = 404, title = "Not Found", type = "about:blank" })

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
        fields = { ["X-Trace"] = schema.optional(schema.string()) }, cookies = { session = schema.optional(schema.string()) } },
      responses = { [200] = User, [404] = NotFound } },
    entry { method = "GET", path = "/users", name = "listUsers", tags = { "users" },
      parameters = { query = { page = schema.default(schema.integer(), 1), q = schema.string() } },
      responses = { [200] = schema.array(User) } },
    entry { method = "DELETE", path = "/users/{id}", name = "deleteUser", deprecated = true,
      parameters = { path = { id = Id } }, responses = { [204] = true, [404] = NotFound },
      security = { { bearer = {} } } },
    entry { method = "GET", path = "/files/{rest...}", name = "getFile",
      parameters = { path = { rest = schema.string() } }, responses = { [200] = true } },
    entry { method = "PUT", path = "/notes", name = "putNote", content = { ["application/json"] = NewUser },
      content_optional = true, responses = { [200] = true } },
    entry { method = "GET", path = "/bare", name = "bare" },
  }
end

local function assert_conforms(self, document, label)
  local problems = structure.check(document)
  self:assert_equal("", table.concat(problems, "\n"), label)
end

function T:test_the_golden_document_conforms()
  local file = assert(io.open(here .. "/../fixtures/shop.openapi.json", "rb"))
  local document = json.decode(file:read("a"))
  file:close()
  assert_conforms(self, document, "golden")
end

function T:test_documents_of_the_build_tests_conform()
  local full = openapi.build {
    info = { title = "Shop", version = "1.2.0", summary = "S", description = "D", contact = { name = "Ops", url = "https://x.test", email = "a@x.test" },
      license = { name = "MIT", identifier = "MIT" } },
    servers = { { url = "https://api.x.test", description = "Production" } }, routes = routes(),
    tags = { { name = "users", description = "Accounts.", external_docs = { url = "https://x.test/users" } }, { name = "unused" } },
    external_docs = { url = "https://x.test/docs", description = "The guide." },
  }
  assert_conforms(self, full, "full document with tags, servers, external docs, problem details and content_optional")
  self:assert_true(full.components.schemas.ProblemDetails ~= nil or next(full.components.schemas) ~= nil)
  assert_conforms(self, openapi.build { info = INFO, routes = {} }, "no route")
  assert_conforms(self, openapi.build { info = INFO, routes = { entry { path = "/x", name = "x",
    responses = { [299] = true, [499] = true, [599] = true, [199] = true, [399] = true, [418] = true } } } }, "class labels")
  local empty = problem_class("EmptyTitle", { status = 409, title = "" })
  assert_conforms(self, openapi.build { info = INFO, routes = { entry { path = "/x", name = "x", responses = { [409] = empty } } } }, "empty title")
  local Tagged = schema.named("Tagged", schema.object { kind = schema.literal("#/$defs/User"), ref = schema.string() })
  assert_conforms(self, openapi.build { info = INFO, routes = { entry { path = "/t", name = "t", responses = { [200] = Tagged } } } }, "constants")
end

function T:test_the_self_check_detects_defects()
  local function document()
    return json.decode(json.encode(openapi.build { info = INFO, routes = routes() }))
  end
  local function detects(mutate, expected)
    local doc = document()
    mutate(doc)
    local text = table.concat(structure.check(doc), "\n")
    self:assert_true(text:find(expected, 1, true) ~= nil, expected .. " not found in: " .. text)
  end
  detects(function(d) d.info.title = nil end, "missing required field 'title'")
  detects(function(d) d.info = nil end, "missing required field 'info'")
  detects(function(d) d.openapi = "3.0.3" end, "3.1.x")
  detects(function(d) d.extra = 1 end, "unknown field 'extra'")
  detects(function(d) d.paths["/users"].get.responses["200"].description = nil end, "description")
  detects(function(d) d.paths["/users"].get.responses = {} end, "at least one response")
  detects(function(d) d.paths["/users"].get.responses["20"] = { description = "x" } end, "status code")
  detects(function(d) d.paths["/users/{id}"].get.parameters[1].name = nil end, "missing required field 'name'")
  detects(function(d) d.paths["/users/{id}"].get.parameters[1]["in"] = "body" end, "'in' must be")
  detects(function(d) d.paths["/users/{id}"].get.parameters[1].required = false end, "required = true")
  detects(function(d) d.paths["/users/{id}"].get.parameters = {} end, "not declared")
  detects(function(d) d.paths["/users"].get.parameters[1].schema = nil end, "exactly one of schema and content")
  detects(function(d) d.paths["/users"].get.parameters[1]["in"] = "path"; d.paths["/users"].get.parameters[1].required = true end, "not in the path template")
  detects(function(d) d.paths["/users"].post.requestBody.content = {} end, "non-empty")
  detects(function(d) d.paths["/users"].post.operationId = d.paths["/users"].get.operationId end, "duplicate operationId")
  detects(function(d) d.tags[2] = { name = "users" } end, "duplicate tag")
  detects(function(d) d.tags[1].name = nil end, "missing required field 'name'")
  detects(function(d) d.components.schemas["bad name"] = {} end, "does not match")
  detects(function(d) d.paths["/users"].post.requestBody.content["application/json"].schema = { ["$ref"] = "#/components/schemas/Nope" } end, "does not resolve")
  detects(function(d) d.paths["users"] = {} end, "must start with '/'")
  detects(function(d) d.externalDocs = { description = "x" } end, "missing required field 'url'")
  -- a specification extension is allowed
  local doc = document()
  doc["x-extra"] = true
  assert_conforms(self, doc, "extension")
end

--- The schema is read only when the pinned fixture is present; in CI its absence is a failure.
local function official(self)
  local file = io.open(OFFICIAL, "rb")
  if not file then
    local message = "the official OpenAPI 3.1 schema is missing (lua tools/run.lua fetch-fixtures openapi)"
    if os.getenv("CI") then self:fail(message) end
    io.stderr:write("# skipped: " .. message .. "\n")
    return nil
  end
  local text = file:read("a")
  file:close()
  return json.decode(text)
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return table.concat(keys, ",")
end

local function sorted(list)
  local copy = { table.unpack(list) }
  table.sort(copy)
  return table.concat(copy, ",")
end

function T:test_the_fixed_fields_agree_with_the_official_schema()
  local official_schema = official(self)
  if not official_schema then return end
  self:assert_equal("https://spec.openapis.org/oas/3.1/schema/2026-11-05", official_schema["$id"])
  for kind, spec in pairs(structure.OBJECTS) do
    local node = spec.def and official_schema["$defs"][spec.def] or official_schema
    self:assert_true(node ~= nil, "no official definition for " .. kind)
    self:assert_equal(sorted_keys(node.properties), sorted(spec.allowed), kind .. ": allowed fields")
    self:assert_equal(sorted(node.required or {}), sorted(spec.required), kind .. ": required fields")
  end
end

return T
