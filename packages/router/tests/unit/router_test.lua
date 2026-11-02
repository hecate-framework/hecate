---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local router = require("hecate.router")
local Router = router.Router
local T = test.Case("RouterTest")

local function routes(...) return { ... } end

--- Asserts that `fn` raises an instance of `class`; returns the error.
local function raises(case, class, fn)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, class), tostring(err))
  return err
end

local function names(list)
  local out = {}
  for i, route in ipairs(list) do out[i] = route.name end
  return table.concat(out, ",")
end

-- Matching ---------------------------------------------------------------------------------------------------------

function T:test_a_static_route_matches_its_method_and_path()
  local list = routes({ method = "GET", path = "/users", name = "users.list" })
  local r = Router(list)
  local m = r:match("GET", "/users")
  self:assert_equal(200, m.status)
  self:assert_true(m.route == list[1], "the match gives back the route table as declared")
  self:assert_nil(next(m.parameters))
end

function T:test_a_parameter_segment_is_bound_to_its_decoded_value()
  local r = Router(routes({ method = "GET", path = "/users/{id}/posts/{post}", name = "posts.show" }))
  local m = r:match("GET", "/users/42/posts/h%C3%A9llo%20w%2Frld")
  self:assert_equal(200, m.status)
  self:assert_equal("42", m.parameters.id)
  self:assert_equal("h\195\169llo w/rld", m.parameters.post)
end

function T:test_an_encoded_slash_is_data_and_not_a_separator()
  local r = Router(routes({ method = "GET", path = "/files/{name}" }, { method = "GET", path = "/files/{a}/{b}" }))
  local m = r:match("GET", "/files/x%2Fy")
  self:assert_equal(200, m.status)
  self:assert_equal("x/y", m.parameters.name)
  self:assert_nil(m.parameters.a)
end

function T:test_a_parameter_never_matches_an_empty_segment()
  local r = Router(routes({ method = "GET", path = "/users/{id}" }))
  self:assert_equal(404, r:match("GET", "/users/").status)
  self:assert_equal(404, r:match("GET", "/users//").status)
end

function T:test_a_wildcard_takes_the_rest_of_the_path()
  local r = Router(routes({ method = "GET", path = "/static/{path...}" }))
  local m = r:match("GET", "/static/css/site%20x.css")
  self:assert_equal(200, m.status)
  self:assert_equal("css/site x.css", m.parameters.path)
  self:assert_equal("one", r:match("GET", "/static/one").parameters.path)
  self:assert_equal(404, r:match("GET", "/static").status)
  self:assert_equal(404, r:match("GET", "/static/").status)
  self:assert_equal(404, r:match("GET", "/static/a//b").status)
end

function T:test_a_wildcard_does_not_match_a_segment_holding_an_encoded_slash()
  -- Otherwise "..%2F..%2Fsecret" would reach the action as "../../secret".
  local r = Router(routes({ method = "GET", path = "/static/{path...}" }))
  self:assert_equal(404, r:match("GET", "/static/..%2F..%2Fsecret").status)
  self:assert_equal(404, r:match("GET", "/static/a/b%2Fc").status)
end

function T:test_precedence_is_static_then_parameter_then_wildcard()
  local r = Router(routes(
    { method = "GET", path = "/a/{x}", name = "param" },
    { method = "GET", path = "/a/{rest...}", name = "wild" },
    { method = "GET", path = "/a/b", name = "static" }))
  self:assert_equal("static", r:match("GET", "/a/b").route.name)
  self:assert_equal("param", r:match("GET", "/a/c").route.name)
  self:assert_equal("wild", r:match("GET", "/a/c/d").route.name)
end

function T:test_matching_backtracks_from_a_static_prefix_to_a_parameter()
  local r = Router(routes(
    { method = "GET", path = "/a/b/c", name = "static" },
    { method = "GET", path = "/a/{x}/d", name = "param" },
    { method = "GET", path = "/{y...}", name = "wild" }))
  self:assert_equal("static", r:match("GET", "/a/b/c").route.name)
  self:assert_equal("param", r:match("GET", "/a/b/d").route.name)
  local m = r:match("GET", "/a/b/e")
  self:assert_equal("wild", m.route.name)
  self:assert_equal("a/b/e", m.parameters.y)
end

function T:test_parameters_are_bound_by_position_whatever_the_names()
  local r = Router(routes(
    { method = "GET", path = "/u/{id}/a", name = "first" },
    { method = "GET", path = "/u/{user}/b", name = "second" }))
  self:assert_equal("7", r:match("GET", "/u/7/a").parameters.id)
  self:assert_equal("7", r:match("GET", "/u/7/b").parameters.user)
  self:assert_nil(r:match("GET", "/u/7/b").parameters.id)
end

function T:test_a_path_with_no_route_is_404()
  local r = Router(routes({ method = "GET", path = "/a" }))
  local m = r:match("GET", "/b")
  self:assert_equal(404, m.status)
  self:assert_nil(m.route)
  self:assert_nil(m.allow)
  self:assert_equal(404, r:match("GET", "/a/b").status)
  self:assert_equal(404, r:match("GET", "/").status)
end

function T:test_matching_is_case_sensitive()
  local r = Router(routes({ method = "GET", path = "/Users" }))
  self:assert_equal(404, r:match("GET", "/users").status)
end

-- 405 and Allow ----------------------------------------------------------------------------------------------------

function T:test_a_known_path_with_another_method_is_405_with_a_sorted_allow()
  local r = Router(routes(
    { method = "POST", path = "/things" },
    { method = { "GET", "DELETE" }, path = "/things" }),
    { automatic_head = false, automatic_options = false })
  local m = r:match("PUT", "/things")
  self:assert_equal(405, m.status)
  self:assert_equal("DELETE, GET, POST", m.allow_field)
  self:assert_equal(3, #m.allow)
  self:assert_equal("DELETE", m.allow[1])
  self:assert_equal("POST", m.allow[3])
end

function T:test_allow_lists_the_methods_of_every_route_the_path_matches()
  local r = Router(routes(
    { method = "GET", path = "/users/me" },
    { method = "DELETE", path = "/users/{id}" }),
    { automatic_head = false, automatic_options = false })
  local m = r:match("POST", "/users/me")
  self:assert_equal(405, m.status)
  self:assert_equal("DELETE, GET", m.allow_field)
  -- DELETE reaches the parameter route because the static route does not serve it.
  self:assert_equal(200, r:match("DELETE", "/users/me").status)
  self:assert_equal("me", r:match("DELETE", "/users/me").parameters.id)
end

function T:test_the_allow_of_a_405_includes_the_automatic_methods()
  local r = Router(routes({ method = "GET", path = "/a" }))
  self:assert_equal("GET, HEAD, OPTIONS", r:match("POST", "/a").allow_field)
end

function T:test_methods_are_case_sensitive_tokens()
  local r = Router(routes({ method = "GET", path = "/a" }))
  self:assert_equal(405, r:match("get", "/a").status)
end

-- Automatic HEAD and OPTIONS ---------------------------------------------------------------------------------------

function T:test_head_is_served_by_the_get_route_unless_one_is_declared()
  local r = Router(routes({ method = "GET", path = "/a", name = "get" }))
  local m = r:match("HEAD", "/a")
  self:assert_equal(200, m.status)
  self:assert_equal("get", m.route.name)
  local explicit = Router(routes({ method = "GET", path = "/a", name = "get" }, { method = "HEAD", path = "/a", name = "head" }))
  self:assert_equal("head", explicit:match("HEAD", "/a").route.name)
  local off = Router(routes({ method = "GET", path = "/a" }), { automatic_head = false })
  self:assert_equal(405, off:match("HEAD", "/a").status)
  self:assert_equal("GET, OPTIONS", off:match("HEAD", "/a").allow_field)
end

function T:test_options_answers_204_with_the_allowed_methods_unless_a_route_is_declared()
  local r = Router(routes({ method = { "GET", "POST" }, path = "/a" }))
  local m = r:match("OPTIONS", "/a")
  self:assert_equal(204, m.status)
  self:assert_equal("GET, HEAD, OPTIONS, POST", m.allow_field)
  self:assert_nil(m.route)
  local explicit = Router(routes({ method = "OPTIONS", path = "/a", name = "o" }))
  self:assert_equal("o", explicit:match("OPTIONS", "/a").route.name)
  local off = Router(routes({ method = "GET", path = "/a" }), { automatic_options = false })
  self:assert_equal(405, off:match("OPTIONS", "/a").status)
  self:assert_equal(404, r:match("OPTIONS", "/nothing").status)
end

-- Trailing slash ---------------------------------------------------------------------------------------------------

function T:test_the_trailing_slash_is_significant_by_default()
  local r = Router(routes({ method = "GET", path = "/a", name = "a" }, { method = "GET", path = "/b/", name = "b" }, { method = "GET", path = "/", name = "root" }))
  self:assert_equal("a", r:match("GET", "/a").route.name)
  self:assert_equal(404, r:match("GET", "/a/").status)
  self:assert_equal("b", r:match("GET", "/b/").route.name)
  self:assert_equal(404, r:match("GET", "/b").status)
  self:assert_equal("root", r:match("GET", "/").route.name)
end

function T:test_the_ignore_policy_serves_both_forms()
  local r = Router(routes({ method = "GET", path = "/a", name = "a" }, { method = "GET", path = "/b/", name = "b" }, { method = "GET", path = "/", name = "root" }),
    { trailing_slash = "ignore" })
  for _, path in ipairs({ "/a", "/a/" }) do self:assert_equal("a", r:match("GET", path).route.name) end
  for _, path in ipairs({ "/b", "/b/" }) do self:assert_equal("b", r:match("GET", path).route.name) end
  self:assert_equal("root", r:match("GET", "/").route.name)
end

function T:test_two_templates_that_differ_by_a_trailing_slash_conflict_under_ignore()
  raises(self, router.RouteTableError, function()
    Router(routes({ method = "GET", path = "/a" }, { method = "GET", path = "/a/" }), { trailing_slash = "ignore" })
  end)
  Router(routes({ method = "GET", path = "/a" }, { method = "GET", path = "/a/" }))
end

-- Path normalisation (OQ-75) ---------------------------------------------------------------------------------------

function T:test_dot_segments_are_resolved_before_matching()
  local r = Router(routes({ method = "GET", path = "/a/b", name = "b" }, { method = "GET", path = "/c", name = "c" }))
  self:assert_equal("b", r:match("GET", "/a/./b").route.name)
  self:assert_equal("b", r:match("GET", "/a/x/../b").route.name)
  self:assert_equal("b", r:match("GET", "/../../a/b").route.name)
  self:assert_equal("c", r:match("GET", "/a/%2e%2e/c").route.name)
  self:assert_equal("c", r:match("GET", "/a/b/../../c").route.name)
end

function T:test_dot_segments_cannot_reach_beyond_the_root()
  local r = Router(routes({ method = "GET", path = "/secret" }))
  self:assert_equal(200, r:match("GET", "/public/../../secret").status)
end

function T:test_a_malformed_or_unreadable_path_is_a_400_with_a_reason()
  local r = Router(routes({ method = "GET", path = "/a/{x}" }))
  local cases = {
    { "/a/%zz", "malformed_percent_encoding" }, { "/a/%", "malformed_percent_encoding" }, { "/a/%00", "encoded_nul" },
    { "*", "not_absolute" }, { "", "not_absolute" }, { "a", "not_absolute" },
  }
  for _, case in ipairs(cases) do
    local m = r:match("GET", case[1])
    self:assert_equal(400, m.status, case[1])
    self:assert_equal(case[2], m.reason, case[1])
    self:assert_nil(m.route)
  end
end

function T:test_match_refuses_arguments_that_are_not_strings()
  local r = Router(routes({ method = "GET", path = "/a" }))
  raises(self, core.ArgumentError, function() r:match(nil, "/a") end)
  raises(self, core.ArgumentError, function() r:match("GET", nil) end)
  raises(self, core.ArgumentError, function() r:match("", "/a") end)
end

-- Route table checks at boot ---------------------------------------------------------------------------------------

function T:test_ambiguous_routes_are_rejected_with_both_routes_named()
  local err = raises(self, router.RouteTableError, function()
    Router(routes(
      { method = "GET", path = "/users/{id}", name = "first" },
      { method = "POST", path = "/other" },
      { method = "GET", path = "/users/{user}", name = "second" }))
  end)
  self:assert_equal("ambiguous_route", err.context.reason)
  self:assert_equal(3, err.context.index)
  self:assert_equal(1, err.context.other_index)
  self:assert_equal("GET", err.context.method)
  self:assert_true(err.message:find("/users/{id}", 1, true) ~= nil, err.message)
  self:assert_true(err.message:find("/users/{user}", 1, true) ~= nil, err.message)
  self:assert_true(err.message:find("first", 1, true) ~= nil, err.message)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError))
end

function T:test_the_same_template_with_another_method_is_not_ambiguous()
  Router(routes({ method = "GET", path = "/a/{x}" }, { method = "POST", path = "/a/{y}" }))
end

function T:test_a_method_list_that_overlaps_another_route_is_ambiguous()
  local err = raises(self, router.RouteTableError, function()
    Router(routes({ method = { "GET", "POST" }, path = "/a" }, { method = "POST", path = "/a" }))
  end)
  self:assert_equal("ambiguous_route", err.context.reason)
  self:assert_equal("POST", err.context.method)
end

function T:test_two_wildcards_at_one_position_are_ambiguous_but_a_wildcard_and_a_parameter_are_not()
  raises(self, router.RouteTableError, function()
    Router(routes({ method = "GET", path = "/a/{x...}" }, { method = "GET", path = "/a/{y...}" }))
  end)
  Router(routes({ method = "GET", path = "/a/{x...}" }, { method = "GET", path = "/a/{y}" }, { method = "GET", path = "/a/b" }))
end

function T:test_duplicate_route_names_are_rejected()
  local err = raises(self, router.RouteTableError, function()
    Router(routes({ method = "GET", path = "/a", name = "n" }, { method = "GET", path = "/b", name = "n" }))
  end)
  self:assert_equal("duplicate_name", err.context.reason)
end

function T:test_an_invalid_template_is_rejected_with_its_reason_and_route()
  local err = raises(self, router.RouteTableError, function()
    Router(routes({ method = "GET", path = "/ok" }, { method = "GET", path = "/x{id...}" }))
  end)
  self:assert_equal("invalid_template", err.context.reason)
  self:assert_equal("mixed_segment", err.context.template_reason)
  self:assert_equal(2, err.context.index)
  self:assert_true(err.message:find("/x{id...}", 1, true) ~= nil, err.message)
end

function T:test_invalid_routes_are_rejected()
  local bad = {
    { "invalid_route", 42 },
    { "invalid_route", { path = "/a" } },
    { "invalid_route", { method = "GET" } },
    { "invalid_route", { method = "GET", path = "/a", name = "" } },
    { "invalid_route", { method = "GET", path = "/a", name = 5 } },
    { "invalid_method", { method = "", path = "/a" } },
    { "invalid_method", { method = "G ET", path = "/a" } },
    { "invalid_method", { method = {}, path = "/a" } },
    { "invalid_method", { method = { "GET", "GET" }, path = "/a" } },
    { "invalid_method", { method = 5, path = "/a" } },
  }
  for _, case in ipairs(bad) do
    local err = raises(self, router.RouteTableError, function() Router({ case[2] }) end)
    self:assert_equal(case[1], err.context.reason, case[1])
    self:assert_equal(1, err.context.index)
  end
end

function T:test_bad_arguments_and_options_are_argument_errors()
  raises(self, core.ArgumentError, function() Router(nil) end)
  raises(self, core.ArgumentError, function() Router("x") end)
  raises(self, core.ArgumentError, function() Router({}, { trailing_slash = "redirect" }) end)
  raises(self, core.ArgumentError, function() Router({}, { automatic_head = "yes" }) end)
  raises(self, core.ArgumentError, function() Router({}, { automatic_heads = true }) end)
  raises(self, core.ArgumentError, function() Router({}, "strict") end)
end

function T:test_an_empty_route_table_is_valid_and_answers_404()
  self:assert_equal(404, Router({}):match("GET", "/").status)
end

function T:test_the_router_is_compiled_at_construction_and_does_not_see_later_changes()
  local list = routes({ method = "GET", path = "/a", name = "a" })
  local r = Router(list)
  list[2] = { method = "GET", path = "/b", name = "b" }
  self:assert_equal(404, r:match("GET", "/b").status)
  self:assert_equal(1, #r:routes())
end

-- Introspection ----------------------------------------------------------------------------------------------------

function T:test_routes_lists_the_declared_routes_in_order()
  local list = routes({ method = "GET", path = "/b", name = "b" }, { method = "GET", path = "/a", name = "a" }, { method = "POST", path = "/c" })
  local r = Router(list)
  local out = r:routes()
  self:assert_equal(3, #out)
  self:assert_true(out[1] == list[1] and out[3] == list[3])
  self:assert_equal("b,a,", names(out) .. ",")
  out[1] = nil -- the list is a copy
  self:assert_equal(3, #r:routes())
end

function T:test_route_finds_a_route_by_name()
  local list = routes({ method = "GET", path = "/a", name = "a" })
  local r = Router(list)
  self:assert_true(r:route("a") == list[1])
  self:assert_nil(r:route("missing"))
end

-- Reverse routing --------------------------------------------------------------------------------------------------

function T:test_url_for_builds_the_path_of_a_named_route()
  local r = Router(routes(
    { method = "GET", path = "/users/{id}", name = "users.show" },
    { method = "GET", path = "/users", name = "users.list" },
    { method = "GET", path = "/static/{path...}", name = "static" }))
  self:assert_equal("/users/42", r:url_for("users.show", { id = 42 }))
  self:assert_equal("/users/a%2Fb%20c", r:url_for("users.show", { id = "a/b c" }))
  self:assert_equal("/users", r:url_for("users.list"))
  self:assert_equal("/static/css/a%20b.css", r:url_for("static", { path = "css/a b.css" }))
end

function T:test_url_for_round_trips_through_match()
  local r = Router(routes(
    { method = "GET", path = "/a/{x}/b/{y}", name = "ab" },
    { method = "GET", path = "/f/{rest...}", name = "f" }))
  local values = { "plain", "with space", "sl/ash", "per%cent", "\195\169", "a.b", "...", "~-_", "?#[]@!$&'()*+,;=", "%2F" }
  for _, x in ipairs(values) do
    local url = r:url_for("ab", { x = x, y = "2" })
    local m = r:match("GET", url)
    self:assert_equal(200, m.status, url)
    self:assert_equal(x, m.parameters.x, url)
    self:assert_equal("2", m.parameters.y, url)
  end
  for _, rest in ipairs({ "a", "a/b", "a b/c%d/\195\169", "x/.../y" }) do
    local m = r:match("GET", r:url_for("f", { rest = rest }))
    self:assert_equal(rest, m.parameters.rest)
  end
end

function T:test_url_for_keeps_the_declared_trailing_slash_and_literal_encoding()
  local r = Router(routes({ method = "GET", path = "/a%20b/", name = "n" }))
  self:assert_equal("/a%20b/", r:url_for("n"))
end

function T:test_url_for_refuses_what_it_cannot_build()
  local r = Router(routes({ method = "GET", path = "/u/{id}", name = "u" }, { method = "GET", path = "/anon" }))
  raises(self, core.ArgumentError, function() r:url_for("missing") end)
  raises(self, core.ArgumentError, function() r:url_for(nil) end)
  raises(self, core.ArgumentError, function() r:url_for("u") end)
  raises(self, core.ArgumentError, function() r:url_for("u", { id = 1, extra = 2 }) end)
  raises(self, core.ArgumentError, function() r:url_for("u", { id = ".." }) end)
  raises(self, core.ArgumentError, function() r:url_for("u", "42") end)
end

-- Review follow-ups -------------------------------------------------------------------------------------------------

function T:test_route_and_a_map_of_routes_are_checked()
  local r = Router(routes({ method = "GET", path = "/a", name = "a" }))
  raises(self, core.ArgumentError, function() r:route(1) end)
  raises(self, core.ArgumentError, function() Router({ home = { method = "GET", path = "/" } }) end)
end

function T:test_encoded_slash_and_backslash_stay_data_in_a_parameter()
  local r = Router(routes({ method = "GET", path = "/f/{id}" }))
  local m = r:match("GET", "/f/..%2F..")
  self:assert_equal(200, m.status)
  self:assert_equal("../..", m.parameters.id)
  self:assert_equal("a\\b", r:match("GET", "/f/a%5Cb").parameters.id)
  self:assert_equal("a\r\nb", r:match("GET", "/f/a%0D%0Ab").parameters.id)
end

function T:test_a_wildcard_never_takes_an_encoded_slash_as_a_separator_and_dots_resolve_before_matching()
  local r = Router(routes({ method = "GET", path = "/s/{p...}" }, { method = "GET", path = "/x" }))
  self:assert_equal(200, r:match("GET", "/s/a/%2e%2E/../x").status)
  self:assert_equal(405, r:match("POST", "/s/a/../../x").status)
  self:assert_equal("/x", r:match("GET", "/s/%2E%2e/x").route.path)
end

function T:test_a_very_long_path_matches_without_trouble()
  local r = Router(routes({ method = "GET", path = "/{a}/{b}/{rest...}" }))
  local long = "/x/y" .. string.rep("/seg", 20000)
  self:assert_equal(200, r:match("GET", long).status)
end


-- A parameter inside a segment (RFC 6570 level 1: literal text around one expression) ---------------------------------

local function affixed_router()
  return Router(routes(
    { method = "GET", path = "/files/{name}.json", name = "json" },
    { method = "GET", path = "/files/{name}.xml", name = "xml" },
    { method = "GET", path = "/files/{name}", name = "plain" },
    { method = "GET", path = "/files/report.json", name = "report" },
    { method = "GET", path = "/v{major}", name = "version" },
    { method = "GET", path = "/u/x{id}y", name = "both" },
    { method = "POST", path = "/files/{name}.json", name = "post" }))
end

function T:test_a_parameter_with_literal_text_around_it_binds_the_rest_of_the_segment()
  local r = affixed_router()
  local m = r:match("GET", "/files/data.json")
  self:assert_equal("json", m.route.name)
  self:assert_equal("data", m.parameters.name)
  self:assert_equal("xml", r:match("GET", "/files/a.b.xml").route.name)
  self:assert_equal("a.b", r:match("GET", "/files/a.b.xml").parameters.name)
  self:assert_equal("2", r:match("GET", "/v2").parameters.major)
  self:assert_equal("42", r:match("GET", "/u/x42y").parameters.id)
end

function T:test_precedence_is_static_then_affixed_then_parameter()
  local r = affixed_router()
  self:assert_equal("report", r:match("GET", "/files/report.json").route.name)
  self:assert_equal("plain", r:match("GET", "/files/data.txt").route.name)
  self:assert_equal("plain", r:match("GET", "/files/data.jsonx").route.name)
end

function T:test_an_affixed_parameter_needs_a_non_empty_value()
  local r = affixed_router()
  self:assert_equal("plain", r:match("GET", "/files/.json").route.name)
  self:assert_equal(404, r:match("GET", "/v").status)
  self:assert_equal(404, r:match("GET", "/u/xy").status)
  self:assert_equal(404, r:match("GET", "/u/x").status)
end

function T:test_the_value_of_an_affixed_parameter_is_decoded()
  local r = affixed_router()
  self:assert_equal("a/b", r:match("GET", "/files/a%2Fb.json").parameters.name)
  self:assert_equal("data", r:match("GET", "/files/data%2Ejson").parameters.name)
end

function T:test_an_affixed_route_that_does_not_serve_the_method_falls_through_and_feeds_allow()
  local r = affixed_router()
  self:assert_equal("post", r:match("POST", "/files/x.json").route.name)
  local m = r:match("DELETE", "/files/x.json")
  self:assert_equal(405, m.status)
  self:assert_equal("GET, HEAD, OPTIONS, POST", m.allow_field)
end

function T:test_url_for_expands_text_around_a_parameter()
  local r = affixed_router()
  self:assert_equal("/files/a%20b.json", r:url_for("json", { name = "a b" }))
  self:assert_equal("/v2", r:url_for("version", { major = 2 }))
  self:assert_equal("/u/x7y", r:url_for("both", { id = 7 }))
  self:assert_equal("/files/..json", r:url_for("json", { name = "." }))
  local round = r:match("GET", r:url_for("json", { name = "a/b" }))
  self:assert_equal("a/b", round.parameters.name)
end

function T:test_url_for_refuses_a_value_that_would_form_a_dot_segment()
  local r = Router(routes({ method = "GET", path = "/.{x}", name = "dot" }))
  raises(self, core.ArgumentError, function() r:url_for("dot", { x = "." }) end)
  self:assert_equal("/.a", r:url_for("dot", { x = "a" }))
end

function T:test_identical_affixed_templates_are_ambiguous()
  local err = raises(self, router.RouteTableError, function()
    Router(routes({ method = "GET", path = "/a/{x}.json" }, { method = "GET", path = "/a/{y}.json" }))
  end)
  self:assert_equal("ambiguous_route", err.context.reason)
end

return T
