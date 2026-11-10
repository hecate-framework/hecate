---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field  -- the tests pass invalid declarations on purpose
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local router = require("hecate.router")
local kernel = require("hecate.kernel")
local problem = require("hecate.kernel.problem")
local T = test.Case("RoutesTest")

local RouteDeclarationError = kernel.RouteDeclarationError
local Controller = kernel.Controller

--- Asserts that `fn` raises a `RouteDeclarationError` with `reason`; returns the error.
local function refused(case, reason, fn)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, RouteDeclarationError), tostring(err))
  case:assert_equal(reason, err.context.reason)
  return err
end

local User = schema.object { id = schema.integer(), name = schema.string() }
local Id = schema.integer { minimum = 1 }

local function action() return nil end

--- Declares the same route under the two styles and returns both entries.
local function pair(spec)
  local module = kernel.routes("users")
  local declared = {}
  for key, value in pairs(spec) do declared[key] = value end
  declared.method, declared.path = nil, nil
  module[spec.method:lower()](module, spec.path, { action = action, summary = spec.summary, parameters = spec.parameters,
    responses = spec.responses, tags = spec.tags, deprecated = spec.deprecated, name = spec.name, content = spec.content })

  local Users = core.class("UsersController", Controller)
  Users.prefix = "/users"
  Controller.route(Users, {
    method = spec.method, path = spec.path:sub(#"/users" + 1) == "" and "/" or spec.path:sub(#"/users" + 1),
    action = "act", summary = spec.summary, parameters = spec.parameters, responses = spec.responses, tags = spec.tags,
    deprecated = spec.deprecated, name = spec.name, content = spec.content,
  })
  Users.act = action
  core.finalise(Users)
  return module:routes()[1], Controller.routes(Users)[1]
end

--- Structural equality; the same table (a schema, a problem class) is equal to itself.
local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" or core.is_class(a) or schema.is_schema(a) then return false end
  for key, value in pairs(a) do
    if not deep_equal(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

--- Compares two entries apart from the fields that differ by nature (action, controller, origin).
local function same(case, a, b)
  local function strip(entry)
    local copy = {}
    for key, value in pairs(entry) do
      if key ~= "action" and key ~= "controller" and key ~= "origin" then copy[key] = value end
    end
    return copy
  end
  case:assert_true(deep_equal(strip(a), strip(b)), "the two styles produced different entries")
end

function T:test_both_styles_produce_identical_route_tables()
  local a, b = pair {
    method = "GET", path = "/users/{id}", summary = "Fetch a user", tags = { "users" },
    parameters = { path = { id = Id }, query = { verbose = schema.optional(schema.boolean()) } },
    responses = { [200] = User, [404] = problem.NotFound },
  }
  same(self, a, b)
  self:assert_equal("GET /users/{id}", a.name)
  self:assert_equal("act", b.action)
  self:assert_true(a.action == action)
end

function T:test_both_styles_agree_on_the_prefix_itself_and_other_methods()
  for _, method in ipairs({ "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS" }) do
    local a, b = pair { method = method, path = "/users", name = "x." .. method, content = { ["application/json"] = User } }
    same(self, a, b)
    self:assert_equal(method, a.method)
  end
end

function T:test_whole_tables_are_equal_and_router_accepts_them()
  local module = kernel.routes("health")
  module:get "/health" { action = action, responses = { [200] = User } }
  module:post "/things/{id}" { action = action, parameters = { path = { id = Id } } }
  local Things = core.class("ThingsController", Controller)
  Things.prefix = "/things"
  Controller.route(Things, { method = "GET", path = "/{id}", action = "show", parameters = { path = { id = Id } } })
  Things.show = action
  core.finalise(Things)
  local entries = kernel.routing.collect({ module, Things })
  self:assert_equal(3, #entries)
  local compiled = router.Router(entries)
  self:assert_equal(200, compiled:match("GET", "/things/3").status)
  self:assert_equal("3", compiled:match("GET", "/things/3").parameters.id)
  self:assert_equal(405, compiled:match("DELETE", "/health").status)
end

function T:test_entry_shape_is_complete_with_defaults()
  local module = kernel.routes("m")
  module:get("/x", { action = action })
  local entry = module:routes()[1]
  self:assert_equal("GET /x", entry.name)
  self:assert_equal(false, entry.deprecated)
  for _, field in ipairs({ "tags", "content", "responses", "security", "filters" }) do
    self:assert_equal("table", type(entry[field]), field)
  end
  for _, location in ipairs({ "path", "query", "fields", "cookies" }) do
    self:assert_equal("table", type(entry.parameters[location]), location)
  end
  self:assert_equal("route module m", entry.origin)
end

function T:test_chained_and_direct_spellings_are_the_same()
  local a, b = kernel.routes("m"), kernel.routes("m")
  a:get "/x" { action = action }
  b:get("/x", { action = action })
  same(self, a:routes()[1], b:routes()[1])
  self:assert_true(a:get("/y", { action = action }) == a)
end

function T:test_routes_returns_a_copy_in_declaration_order()
  local module = kernel.routes("m")
  module:get "/a" { action = action }
  module:get "/b" { action = action }
  local list = module:routes()
  list[1] = nil
  self:assert_equal("/a", module:routes()[1].path)
  self:assert_equal("/b", module:routes()[2].path)
end

function T:test_route_module_name_must_be_non_empty_string()
  self:assert_true(core.is_instance_of(self:assert_error(function() kernel.routes("") end), core.ArgumentError))
  self:assert_true(core.is_instance_of(self:assert_error(function() kernel.routes(nil) end), core.ArgumentError))
end

function T:test_verb_arguments_are_checked()
  local module = kernel.routes("m")
  self:assert_true(core.is_instance_of(self:assert_error(function() module:get(1, {}) end), core.ArgumentError))
  self:assert_true(core.is_instance_of(self:assert_error(function() module:get("/x", 3) end), core.ArgumentError))
  self:assert_true(core.is_instance_of(self:assert_error(function()
    module:get("/x", { path = "/y", action = action })
  end), core.ArgumentError))
end

function T:test_path_parameters_must_match_the_template_both_ways()
  local module = kernel.routes("m")
  local missing = refused(self, "parameter_mismatch", function() module:get "/u/{id}" { action = action } end)
  self:assert_true(missing.message:find("{id}", 1, true) ~= nil)
  refused(self, "parameter_mismatch", function()
    module:get "/u" { action = action, parameters = { path = { id = Id } } }
  end)
  refused(self, "parameter_mismatch", function()
    module:get "/u/{id}" { action = action, parameters = { path = { id = Id, other = Id } } }
  end)
  module:get "/files/{path...}" { action = action, parameters = { path = { path = schema.string() } } }
  self:assert_equal(1, #module:routes())
end

function T:test_invalid_shapes_are_refused_with_a_reason()
  local module = kernel.routes("m")
  local function bad(reason, spec) refused(self, reason, function() module:get("/x", spec) end) end
  bad("unknown_field", { action = action, sumary = "typo" })
  bad("invalid_action", {})
  bad("invalid_action", { action = "show" })
  bad("invalid_name", { action = action, name = "" })
  bad("invalid_text", { action = action, summary = 3 })
  bad("invalid_tags", { action = action, tags = "a" })
  bad("invalid_deprecated", { action = action, deprecated = "yes" })
  bad("invalid_parameters", { action = action, parameters = { header = {} } })
  bad("invalid_parameters", { action = action, parameters = { query = { q = "string" } } })
  bad("invalid_content", { action = action, content = { json = User } })
  bad("invalid_content", { action = action, content = { ["application/json"] = 1 } })
  bad("invalid_responses", { action = action, responses = { ["200"] = User } })
  bad("invalid_responses", { action = action, responses = { [200] = {} } })
  bad("invalid_responses", { action = action, responses = { [99] = User } })
  bad("invalid_security", { action = action, security = "bearer" })
  bad("invalid_filters", { action = action, filters = { {} } })
  refused(self, "invalid_path", function() module:get("x", { action = action }) end)
  refused(self, "invalid_path", function() module:get("/a/{b}-{c}", { action = action }) end)
  self:assert_equal(0, #module:routes())
end

function T:test_a_failed_declaration_leaves_the_module_unchanged()
  local module = kernel.routes("m")
  module:get "/a" { action = action }
  refused(self, "invalid_action", function() module:get "/b" {} end)
  self:assert_equal(1, #module:routes())
end

function T:test_error_names_the_origin()
  local err = refused(self, "invalid_action", function() kernel.routes("users"):get("/x", {}) end)
  self:assert_equal("route module users", err.context.origin)
  self:assert_true(err.message:find("route module users", 1, true) ~= nil)
end

function T:test_problem_class_is_a_valid_response()
  local module = kernel.routes("m")
  module:get "/x" { action = action, responses = { [404] = problem.NotFound } }
  self:assert_true(module:routes()[1].responses[404] == problem.NotFound)
end

function T:test_filters_of_a_controller_come_before_those_of_the_route()
  local outer, inner = { handle = function() end }, { handle = function() end }
  local Users = core.class("UsersController", Controller)
  Users.filters = { outer }
  Controller.route(Users, { method = "GET", path = "/x", action = "act", filters = { inner } })
  Users.act = action
  core.finalise(Users)
  local filters = Controller.routes(Users)[1].filters
  self:assert_true(filters[1] == outer and filters[2] == inner)
end

function T:test_controller_declared_methods_may_come_after_the_declaration()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", action = "late" })
  function Users:late() end
  core.finalise(Users)
  self:assert_equal("late", Controller.routes(Users)[1].action)
  self:assert_equal("GET /x", Controller.routes(Users)[1].name)
end

function T:test_controller_missing_action_is_a_boot_error()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", action = "nothing" })
  core.finalise(Users)
  local err = refused(self, "missing_action", function() Controller.routes(Users) end)
  self:assert_equal("controller UsersController", err.context.origin)
end

function T:test_controller_declaration_is_validated_at_once()
  local Users = core.class("UsersController", Controller)
  refused(self, "parameter_mismatch", function() Controller.route(Users, { method = "GET", path = "/{id}", action = "a" }) end)
  refused(self, "invalid_method", function() Controller.route(Users, { method = "get", path = "/x", action = "a" }) end)
  refused(self, "invalid_method", function() Controller.route(Users, { path = "/x", action = "a" }) end)
  refused(self, "invalid_action", function() Controller.route(Users, { method = "GET", path = "/x", action = action }) end)
  self:assert_equal(0, #(function() core.finalise(Users) return Controller.routes(Users) end)())
end

function T:test_controller_routes_need_a_finalised_controller_class()
  local Users = core.class("UsersController", Controller)
  refused(self, "invalid_controller", function() Controller.routes(Users) end)
  refused(self, "invalid_controller", function() Controller.routes({}) end)
  refused(self, "invalid_controller", function() Controller.routes(core.class("Other")) end)
  self:assert_true(core.is_instance_of(self:assert_error(function()
    Controller.route(core.class("Other"), { method = "GET", path = "/x", action = "a" })
  end), core.ArgumentError))
end

function T:test_prefix_is_validated_when_routes_are_read()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", action = "a" })
  Users.prefix = "users/"
  Users.a = action
  core.finalise(Users)
  refused(self, "invalid_path", function() Controller.routes(Users) end)
end

function T:test_routes_of_a_controller_are_not_inherited()
  local Base = core.class("BaseController", Controller)
  Controller.route(Base, { method = "GET", path = "/x", action = "a" })
  Base.a = action
  core.finalise(Base)
  local Sub = core.class("SubController", Base)
  core.finalise(Sub)
  self:assert_equal(1, #Controller.routes(Base))
  self:assert_equal(0, #Controller.routes(Sub))
end

function T:test_collect_refuses_other_sources_and_router_refuses_duplicates()
  refused(self, "invalid_source", function() kernel.routing.collect({ {} }) end)
  local a, b = kernel.routes("a"), kernel.routes("b")
  a:get "/x" { action = action }
  b:get "/x" { action = action }
  local err = self:assert_error(function() router.Router(kernel.routing.collect({ a, b })) end)
  self:assert_true(core.is_instance_of(err, router.RouteTableError))
end

return T
