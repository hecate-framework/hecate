---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch  -- the tests pass invalid declarations on purpose
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
    responses = spec.responses, tags = spec.tags, deprecated = spec.deprecated, name = spec.name, content = spec.content,
    content_optional = spec.content_optional })

  local Users = core.class("UsersController", Controller)
  Users.prefix = "/users"
  Controller.route(Users, {
    method = spec.method, path = spec.path:sub(#"/users" + 1) == "" and "/" or spec.path:sub(#"/users" + 1),
    action = "act", summary = spec.summary, parameters = spec.parameters, responses = spec.responses, tags = spec.tags,
    deprecated = spec.deprecated, name = spec.name, content = spec.content,
    content_optional = spec.content_optional,
  })
  Users.act = action
  core.finalise(Users)
  return module:routes()[1], Controller.entries(Users)[1]
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
    method = "GET", path = "/users/{id}", name = "get_users_id", summary = "Fetch a user", tags = { "users" },
    parameters = { path = { id = Id }, query = { verbose = schema.optional(schema.boolean()) } },
    responses = { [200] = User, [404] = problem.NotFound },
  }
  same(self, a, b)
  self:assert_equal("get_users_id", a.name)
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
  module:get "/health" { name = "get_health", action = action, responses = { [200] = User } }
  module:post "/things/{id}" { name = "post_things_id", action = action, parameters = { path = { id = Id } } }
  local Things = core.class("ThingsController", Controller)
  Things.prefix = "/things"
  Controller.route(Things, { method = "GET", path = "/{id}", name = "get_id", action = "show", parameters = { path = { id = Id } } })
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
  module:get("/x", { name = "get_x", action = action })
  local entry = module:routes()[1]
  self:assert_equal("get_x", entry.name)
  self:assert_equal(false, entry.deprecated)
  self:assert_equal(false, entry.content_optional)
  for _, field in ipairs({ "tags", "content", "responses", "security", "filters" }) do
    self:assert_equal("table", type(entry[field]), field)
  end
  for _, location in ipairs({ "path", "query", "fields", "cookies" }) do
    self:assert_equal("table", type(entry.parameters[location]), location)
  end
  self:assert_equal("route module m", entry.origin)
end

function T:test_content_optional_is_kept_and_both_styles_agree()
  local a, b = pair({ method = "POST", path = "/users", name = "create", content = { ["application/json"] = User },
    content_optional = true })
  self:assert_equal(true, a.content_optional)
  self:assert_equal(true, b.content_optional)
  local c, d = pair({ method = "POST", path = "/users", name = "create", content = { ["application/json"] = User } })
  self:assert_equal(false, c.content_optional)
  self:assert_equal(false, d.content_optional)
end

function T:test_chained_and_direct_spellings_are_the_same()
  local a, b = kernel.routes("m"), kernel.routes("m")
  a:get "/x" { name = "get_x", action = action }
  b:get("/x", { name = "get_x", action = action })
  same(self, a:routes()[1], b:routes()[1])
  self:assert_true(a:get("/y", { name = "get_y", action = action }) == a)
end

function T:test_routes_returns_a_copy_in_declaration_order()
  local module = kernel.routes("m")
  module:get "/a" { name = "get_a", action = action }
  module:get "/b" { name = "get_b", action = action }
  local list = module:routes()
  list[1] = nil
  self:assert_equal("/a", module:routes()[1].path)
  self:assert_equal("/b", module:routes()[2].path)
end

function T:test_route_module_name_must_be_non_empty_string()
  refused(self, "invalid_argument", function() kernel.routes("") end)
  refused(self, "invalid_argument", function() kernel.routes(nil) end)
end

-- OQ-129 (1): a route has no automatic name; a declaration without `name` is refused, in both styles.
function T:test_a_route_without_a_name_is_refused_in_both_styles()
  local module = kernel.routes("m")
  local err = refused(self, "missing_name", function() module:get("/users/{id}", { action = action, parameters = { path = { id = Id } } }) end)
  self:assert_equal("name", err.context.field)
  self:assert_true(err.message:find('add name = "..."', 1, true) ~= nil, err.message)
  self:assert_true(err.message:find("GET /users/{id}", 1, true) ~= nil, err.message)
  local Users = core.class("UsersController", Controller)
  refused(self, "missing_name", function() Controller.route(Users, { method = "GET", path = "/x", action = "act" }) end)
  local Listed = core.class("ListedController", Controller)
  Listed.routes = { { method = "GET", path = "/x", action = "act" } }
  Listed.act = action
  core.finalise(Listed)
  refused(self, "missing_name", function() Controller.entries(Listed) end)
  for _, name in ipairs({ "", 3 }) do
    refused(self, "invalid_name", function() module:get("/x", { action = action, name = name }) end)
  end
end

function T:test_verb_arguments_are_checked()
  local module = kernel.routes("m")
  refused(self, "invalid_argument", function() module:get(1, {}) end)
  refused(self, "invalid_argument", function() module:get("/x", 3) end)
  refused(self, "invalid_argument", function() module:get("/x", { name = "get_x", path = "/y", action = action }) end)
end

function T:test_path_parameters_must_match_the_template_both_ways()
  local module = kernel.routes("m")
  local missing = refused(self, "parameter_mismatch", function() module:get "/u/{id}" { name = "get_u_id", action = action } end)
  self:assert_true(missing.message:find("{id}", 1, true) ~= nil)
  refused(self, "parameter_mismatch", function()
    module:get "/u" { name = "get_u", action = action, parameters = { path = { id = Id } } }
  end)
  refused(self, "parameter_mismatch", function()
    module:get "/u/{id}" { name = "get_u_id", action = action, parameters = { path = { id = Id, other = Id } } }
  end)
  module:get "/files/{path...}" { name = "get_files_path", action = action, parameters = { path = { path = schema.string() } } }
  self:assert_equal(1, #module:routes())
end

function T:test_invalid_shapes_are_refused_with_a_reason()
  local module = kernel.routes("m")
  local function bad(reason, spec)
    if spec.name == nil then spec.name = "x" end
    refused(self, reason, function() module:get("/x", spec) end)
  end
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
  bad("invalid_content_optional", { action = action, content = { ["application/json"] = User }, content_optional = "yes" })
  bad("invalid_content_optional", { action = action, content_optional = true }) -- no content declared
  bad("invalid_content_optional", { action = action, content_optional = 1 })
  bad("invalid_responses", { action = action, responses = { ["200"] = User } })
  bad("invalid_responses", { action = action, responses = { [200] = {} } })
  bad("invalid_responses", { action = action, responses = { [99] = User } })
  bad("invalid_responses", { action = action, responses = { [204] = false } })
  bad("invalid_security", { action = action, security = "bearer" })
  bad("invalid_filters", { action = action, filters = { {} } })
  refused(self, "invalid_path", function() module:get("x", { action = action }) end)
  refused(self, "invalid_path", function() module:get("/a/{b}-{c}", { name = "get_a_b_c", action = action }) end)
  self:assert_equal(0, #module:routes())
end

function T:test_a_failed_declaration_leaves_the_module_unchanged()
  local module = kernel.routes("m")
  module:get "/a" { name = "get_a", action = action }
  refused(self, "invalid_action", function() module:get "/b" { name = "get_b" } end)
  self:assert_equal(1, #module:routes())
end

function T:test_error_names_the_origin()
  local err = refused(self, "invalid_action", function() kernel.routes("users"):get("/x", { name = "get_x" }) end)
  self:assert_equal("route module users", err.context.origin)
  self:assert_true(err.message:find("route module users", 1, true) ~= nil)
end

function T:test_problem_class_is_a_valid_response()
  local module = kernel.routes("m")
  module:get "/x" { name = "get_x", action = action, responses = { [404] = problem.NotFound } }
  self:assert_true(module:routes()[1].responses[404] == problem.NotFound)
end

function T:test_filters_of_a_controller_come_before_those_of_the_route()
  local outer, inner = { handle = function() end }, { handle = function() end }
  local Users = core.class("UsersController", Controller)
  Users.filters = { outer }
  Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = "act", filters = { inner } })
  Users.act = action
  core.finalise(Users)
  local filters = Controller.entries(Users)[1].filters
  self:assert_true(filters[1] == outer and filters[2] == inner)
end

local function filter() return { handle = function() end } end

function T:test_module_prefix_is_prepended_to_the_path_and_not_to_the_name()
  local module = kernel.routes("admin", { prefix = "/admin" })
  module:get "/users" { name = "get_users", action = action }
  module:get "/" { name = "get_root", action = action }
  local entries = module:routes()
  self:assert_equal("/admin/users", entries[1].path)
  self:assert_equal("get_users", entries[1].name)
  self:assert_equal("/admin", entries[2].path)
  self:assert_equal("get_root", entries[2].name)
end

function T:test_module_default_filters_apply_and_a_route_list_replaces_them()
  local auth, audit, own = filter(), filter(), filter()
  local module = kernel.routes("admin", { filters = { auth, audit } })
  module:get "/a" { name = "get_a", action = action }
  module:get "/b" { name = "get_b", action = action, filters = { own } }
  module:get "/c" { name = "get_c", action = action, filters = {} }
  local entries = module:routes()
  self:assert_true(#entries[1].filters == 2 and entries[1].filters[1] == auth and entries[1].filters[2] == audit)
  self:assert_true(#entries[2].filters == 1 and entries[2].filters[1] == own)
  self:assert_equal(0, #entries[3].filters)
end

function T:test_module_defaults_equal_the_spelled_out_declaration()
  local auth = filter()
  local defaults = kernel.routes("m", { prefix = "/admin", filters = { auth } })
  defaults:get "/users/{id}" { name = "get_users_id", action = action, parameters = { path = { id = Id } } }
  local spelled = kernel.routes("m")
  spelled:get "/admin/users/{id}" { name = "get_users_id", action = action, parameters = { path = { id = Id } }, filters = { auth } }
  same(self, defaults:routes()[1], spelled:routes()[1])
end

function T:test_module_defaults_equal_a_controller_with_the_same_prefix_and_filters()
  local auth = filter()
  local module = kernel.routes("users", { prefix = "/users", filters = { auth } })
  module:get "/{id}" { name = "get_id", action = action, parameters = { path = { id = Id } } }
  module:post "/" { name = "post_root", action = action }
  local Users = core.class("UsersController", Controller)
  Users.prefix, Users.filters = "/users", { auth }
  Controller.route(Users, { method = "GET", path = "/{id}", name = "get_id", action = "act", parameters = { path = { id = Id } } })
  Controller.route(Users, { method = "POST", path = "/", name = "post_root", action = "act" })
  Users.act = action
  core.finalise(Users)
  local a, b = module:routes(), Controller.entries(Users)
  self:assert_equal(2, #a)
  for index = 1, 2 do same(self, a[index], b[index]) end
end

function T:test_module_defaults_do_not_change_controller_filters()
  local outer, inner = filter(), filter()
  local Users = core.class("UsersController", Controller)
  Users.filters = { outer }
  Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = "act", filters = { inner } })
  Users.act = action
  core.finalise(Users)
  local filters = Controller.entries(Users)[1].filters
  self:assert_true(#filters == 2 and filters[1] == outer and filters[2] == inner)
end

function T:test_module_options_are_validated_at_construction()
  refused(self, "unknown_field", function() kernel.routes("m", { prefx = "/a" }) end)
  refused(self, "invalid_options", function() kernel.routes("m", "/a") end)
  refused(self, "invalid_path", function() kernel.routes("m", { prefix = 3 }) end)
  refused(self, "invalid_path", function() kernel.routes("m", { prefix = "admin" }) end)
  refused(self, "invalid_path", function() kernel.routes("m", { prefix = "/admin/" }) end)
  refused(self, "invalid_filters", function() kernel.routes("m", { filters = filter() }) end)
  refused(self, "invalid_filters", function() kernel.routes("m", { filters = { {} } }) end)
  refused(self, "invalid_filters", function() kernel.routes("m", { filters = "auth" }) end)
  self:assert_equal(0, #kernel.routes("m", { prefix = "", filters = {} }):routes())
  refused(self, "invalid_argument", function() kernel.routes("", { prefix = "/a" }) end)
end

function T:test_module_default_filters_are_a_snapshot()
  local auth = filter()
  local list = { auth }
  local module = kernel.routes("m", { filters = list })
  list[2] = filter()
  module:get "/x" { name = "get_x", action = action }
  self:assert_equal(1, #module:routes()[1].filters)
end

function T:test_controller_declared_methods_may_come_after_the_declaration()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = "late" })
  function Users:late() end
  core.finalise(Users)
  self:assert_equal("late", Controller.entries(Users)[1].action)
  self:assert_equal("get_x", Controller.entries(Users)[1].name)
end

function T:test_routes_field_after_route_declarations()
  local Users = core.class("UsersController", Controller)
  Users.prefix = "/users"
  Users.routes = { { method = "GET", path = "/{id}", name = "get_id", action = "show", parameters = { path = { id = Id } } } }
  Controller.route(Users, { method = "GET", path = "/", name = "get_root", action = "list" })
  function Users:list() end
  function Users:show() end
  core.finalise(Users)
  local entries = Controller.entries(Users)
  self:assert_equal(2, #entries)
  self:assert_equal("list", entries[1].action)
  self:assert_equal("show", entries[2].action)
  self:assert_equal("/users/{id}", entries[2].path)
end

function T:test_routes_field_errors_surface_at_boot()
  local Users = core.class("UsersController", Controller)
  Users.routes = { { method = "GET", path = "/x", name = "get_x", action = "nothing" } }
  core.finalise(Users)
  refused(self, "missing_action", function() Controller.entries(Users) end)
  local Bad = core.class("BadController", Controller)
  Bad.routes = "nope"
  core.finalise(Bad)
  refused(self, "invalid_routes", function() Controller.entries(Bad) end)
end

function T:test_controller_missing_action_is_a_boot_error()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = "nothing" })
  core.finalise(Users)
  local err = refused(self, "missing_action", function() Controller.entries(Users) end)
  self:assert_equal("controller UsersController", err.context.origin)
end

function T:test_controller_declaration_is_validated_at_once()
  local Users = core.class("UsersController", Controller)
  refused(self, "parameter_mismatch", function() Controller.route(Users, { method = "GET", path = "/{id}", name = "get_id", action = "a" }) end)
  refused(self, "invalid_method", function() Controller.route(Users, { method = "get", path = "/x", action = "a" }) end)
  refused(self, "invalid_method", function() Controller.route(Users, { path = "/x", action = "a" }) end)
  refused(self, "invalid_action", function() Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = action }) end)
  self:assert_equal(0, #(function() core.finalise(Users) return Controller.entries(Users) end)())
end

function T:test_controller_routes_need_a_finalised_controller_class()
  local Users = core.class("UsersController", Controller)
  refused(self, "invalid_controller", function() Controller.entries(Users) end)
  refused(self, "invalid_controller", function() Controller.entries({}) end)
  refused(self, "invalid_controller", function() Controller.entries(core.class("Other")) end)
  refused(self, "invalid_argument", function()
    Controller.route(core.class("Other"), { method = "GET", path = "/x", name = "get_x", action = "a" })
  end)
end

function T:test_prefix_is_validated_when_routes_are_read()
  local Users = core.class("UsersController", Controller)
  Controller.route(Users, { method = "GET", path = "/x", name = "get_x", action = "a" })
  Users.prefix = "users/"
  Users.a = action
  core.finalise(Users)
  refused(self, "invalid_path", function() Controller.entries(Users) end)
end

function T:test_routes_of_a_controller_are_not_inherited()
  local Base = core.class("BaseController", Controller)
  Controller.route(Base, { method = "GET", path = "/x", name = "get_x", action = "a" })
  Base.a = action
  core.finalise(Base)
  local Sub = core.class("SubController", Base)
  core.finalise(Sub)
  self:assert_equal(1, #Controller.entries(Base))
  self:assert_equal(0, #Controller.entries(Sub))
end

function T:test_a_controller_does_not_inherit_the_prefix_of_its_superclass()
  local Base = core.class("PrefixedBaseController", Controller)
  Base.prefix = "/base"
  Controller.route(Base, { method = "GET", path = "/x", name = "get_x", action = "a" })
  Base.a = action
  core.finalise(Base)
  local Sub = core.class("PrefixedSubController", Base)
  Controller.route(Sub, { method = "GET", path = "/y", name = "get_y", action = "a" })
  core.finalise(Sub)
  self:assert_equal("/base/x", Controller.entries(Base)[1].path)
  self:assert_equal("/y", Controller.entries(Sub)[1].path)
  local Own = core.class("PrefixedOwnController", Base)
  Own.prefix = "/own"
  Controller.route(Own, { method = "GET", path = "/y", name = "get_y", action = "a" })
  core.finalise(Own)
  self:assert_equal("/own/y", Controller.entries(Own)[1].path)
end

function T:test_controller_route_keeps_a_copy_of_the_declaration()
  local Users = core.class("CopiedController", Controller)
  local spec = { method = "GET", path = "/x", name = "get_x", action = "a" }
  Controller.route(Users, spec)
  spec.path, spec.action = "/changed", "other"
  Users.a = action
  core.finalise(Users)
  local entry = Controller.entries(Users)[1]
  self:assert_equal("/x", entry.path)
  self:assert_equal("a", entry.action)
end

function T:test_collect_refuses_other_sources_and_router_refuses_duplicates()
  refused(self, "invalid_source", function() kernel.routing.collect({ {} }) end)
  local a, b = kernel.routes("a"), kernel.routes("b")
  a:get "/x" { name = "get_x", action = action }
  b:get "/x" { name = "get_x", action = action }
  local err = self:assert_error(function() router.Router(kernel.routing.collect({ a, b })) end)
  self:assert_true(core.is_instance_of(err, router.RouteTableError))
end

function T:test_a_prefix_that_is_a_single_slash_is_refused_because_the_prefix_is_then_empty()
  refused(self, "invalid_path", function() kernel.routes("m", { prefix = "/" }) end)
  refused(self, "invalid_path", function() kernel.routes("m", { prefix = "/users/" }) end)
  local module = kernel.routes("m", { prefix = "" })
  module:get("/x", { name = "get_x", action = action })
  self:assert_equal("/x", module:routes()[1].path)
end

function T:test_a_status_declared_with_true_has_no_content_schema()
  local module = kernel.routes("m")
  module:delete "/x" { name = "delete_x", action = action, responses = { [204] = true, [404] = problem.NotFound } }
  local entry = module:routes()[1]
  self:assert_equal(true, entry.responses[204])
  self:assert_equal(problem.NotFound, entry.responses[404])
end

function T:test_a_verb_whose_declarations_were_never_given_is_reported_by_routes()
  local module = kernel.routes("m")
  module:get "/a" { name = "get_a", action = action }
  local _ = module:get "/forgotten" -- the table of declarations is missing: the route would be dropped silently
  local err = refused(self, "incomplete_route", function() module:routes() end)
  self:assert_true(err.message:find("GET /forgotten", 1, true) ~= nil, err.message)
  refused(self, "incomplete_route", function() kernel.routing.collect({ module }) end)
end

function T:test_a_curried_declaration_completed_later_is_not_incomplete()
  local module = kernel.routes("m")
  local pending = module:post "/later"
  pending { name = "post_later", action = action }
  self:assert_equal(1, #module:routes())
end

function T:test_a_curried_declaration_that_is_refused_is_not_reported_as_incomplete()
  local module = kernel.routes("m")
  refused(self, "invalid_action", function() module:get "/bad" { name = "get_bad" } end)
  self:assert_equal(0, #module:routes())
end

-- One API, declared in both styles, from the route table to the answers --------------------------------------------------

--- The same API twice: a route module with a prefix and a default filter, and a controller with the same prefix and filter.
local function both_styles(trace)
  local auth = { handle = function(_, request, next) trace[#trace + 1] = "auth"; return next(request) end }
  local function show(request) return { id = request.parameters.path.id } end
  local function list() return { items = {} } end
  local function create() return { created = true } end
  local function remove() return nil end
  local responses = { [200] = schema.object { id = Id }, [404] = problem.NotFound }
  local created = { [200] = schema.object { created = schema.boolean() } } -- one schema object, shared by both styles

  local module = kernel.routes("users", { prefix = "/users", filters = { auth } })
  module:get "/" { name = "get_root", action = list, summary = "List users", tags = { "users" } }
  module:post "/" { action = create, name = "users.create", responses = created }
  module:get "/{id}" { name = "get_id", action = show, summary = "Fetch a user", parameters = { path = { id = Id } }, responses = responses }
  module:delete "/{id}" { name = "delete_id", action = remove, deprecated = true, parameters = { path = { id = Id } } }

  local Users = core.class("UsersController", Controller)
  Users.prefix, Users.filters = "/users", { auth }
  Controller.route(Users, { method = "GET", path = "/", name = "get_root", action = "list", summary = "List users", tags = { "users" } })
  Controller.route(Users, { method = "POST", path = "/", action = "create", name = "users.create", responses = created })
  Controller.route(Users, { method = "GET", path = "/{id}", name = "get_id", action = "show", summary = "Fetch a user",
    parameters = { path = { id = Id } }, responses = responses })
  Controller.route(Users, { method = "DELETE", path = "/{id}", name = "delete_id", action = "remove", deprecated = true,
    parameters = { path = { id = Id } } })
  Users.list, Users.create, Users.remove = list, create, remove
  function Users:show(request) return show(request) end
  core.finalise(Users)
  return module, Users
end

function T:test_a_whole_api_gives_the_same_route_table_in_both_styles()
  local module, Users = both_styles({})
  local a, b = kernel.routing.collect({ module }), kernel.routing.collect({ Users })
  self:assert_equal(4, #a)
  self:assert_equal(#a, #b)
  for index = 1, #a do
    same(self, a[index], b[index])
    self:assert_equal(a[index].name, b[index].name)
    self:assert_equal(#a[index].filters, #b[index].filters)
    self:assert_true(a[index].filters[1] == b[index].filters[1], "the same filter object in both")
  end
  self:assert_equal("get_root", a[1].name)
  self:assert_equal("users.create", a[2].name)
  self:assert_equal(true, a[4].deprecated)
end

function T:test_a_whole_api_answers_the_same_in_both_styles()
  local json = require("hecate.json")
  local http = require("hecate.http")
  local trace_a, trace_b = {}, {}
  local module = both_styles(trace_a)
  local _, Users = both_styles(trace_b)
  local serve_a = kernel.Application({ routes = { module } }):boot()
  local serve_b = kernel.Application({ routes = { Users } }):boot()
  local probes = {
    { "GET", "/users" }, { "GET", "/users/" }, { "POST", "/users" }, { "GET", "/users/5" }, { "GET", "/users/0" },
    { "GET", "/users/abc" }, { "DELETE", "/users/5" }, { "PUT", "/users/5" }, { "OPTIONS", "/users/5" },
    { "GET", "/users/5/more" }, { "GET", "/nothing" }, { "HEAD", "/users/5" },
  }
  for _, probe in ipairs(probes) do
    local function ask(serve) return serve(http.Request({ method = probe[1], target = probe[2], fields = http.Fields() })) end
    local a, b = ask(serve_a), ask(serve_b)
    local label = probe[1] .. " " .. probe[2]
    self:assert_equal(a.status, b.status, label)
    self:assert_equal(a.content and json.encode(json.decode(a.content)) or nil, b.content and json.encode(json.decode(b.content)) or nil, label)
    self:assert_equal(a.fields:get("Allow"), b.fields:get("Allow"), label)
    self:assert_equal(a.fields:get("Content-Type"), b.fields:get("Content-Type"), label)
  end
  self:assert_equal(table.concat(trace_a, ","), table.concat(trace_b, ","))
  self:assert_true(#trace_a > 0, "the default filter ran")
end

return T
