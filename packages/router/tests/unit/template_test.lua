---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests pass invalid arguments on purpose
-- Path templates: a subset of RFC 6570 level 1 (a whole segment is one `{name}`), plus a trailing `{name...}` wildcard.
local test = require("harness.test")
local core = require("hecate.core")
local template = require("hecate.router.template")
local T = test.Case("TemplateTest")

--- Asserts that `fn` raises a `core.ArgumentError`.
local function refuses(case, fn)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
end

function T:test_parse_reads_static_parameter_and_wildcard_segments()
  local parsed = template.parse("/users/{id}/files/{path...}", "strict")
  self:assert_equal(4, #parsed.segments)
  self:assert_equal("static", parsed.segments[1].kind)
  self:assert_equal("users", parsed.segments[1].value)
  self:assert_equal("parameter", parsed.segments[2].kind)
  self:assert_equal("id", parsed.segments[2].name)
  self:assert_equal("wildcard", parsed.segments[4].kind)
  self:assert_equal("path", parsed.segments[4].name)
  self:assert_equal("id", parsed.names[1])
  self:assert_equal("path", parsed.names[2])
  self:assert_equal("/users/{id}/files/{path...}", parsed.text)
end

function T:test_the_root_template_is_one_empty_static_segment_under_strict_and_none_under_ignore()
  self:assert_equal(1, #template.parse("/", "strict").segments)
  self:assert_equal("", template.parse("/", "strict").segments[1].value)
  self:assert_equal(0, #template.parse("/", "ignore").segments)
  self:assert_equal(2, #template.parse("/a/", "strict").segments)
  self:assert_equal(1, #template.parse("/a/", "ignore").segments)
end

function T:test_literal_segments_are_percent_decoded()
  self:assert_equal("a b", template.parse("/a%20b", "strict").segments[1].value)
  self:assert_equal("a/b", template.parse("/a%2Fb", "strict").segments[1].value)
end

function T:test_invalid_templates_are_refused_with_a_stable_reason()
  local cases = {
    { "users", "not_absolute" },
    { "", "not_absolute" },
    { "/a?x=1", "invalid_character" },
    { "/a#b", "invalid_character" },
    { "/a b", "invalid_character" },
    { "/\195\169", "invalid_character" },
    { "/a//b", "empty_segment" },
    { "//a", "empty_segment" },
    { "/a/./b", "dot_segment" },
    { "/a/..", "dot_segment" },
    { "/%2e%2e/a", "dot_segment" },
    { "/a%zz", "malformed_percent_encoding" },
    { "/a%00", "encoded_nul" },
    { "/{id", "malformed_expression" },
    { "/id}", "malformed_expression" },
    { "/{}", "malformed_expression" },
    { "/{1id}", "malformed_expression" },
    { "/{a-b}", "malformed_expression" },
    { "/{a}{b}", "mixed_segment" },
    { "/{a}-{b}", "mixed_segment" },
    { "/x{id...}", "mixed_segment" },
    { "/{id...}.json", "mixed_segment" },
    { "/{id}{", "malformed_expression" },
    { "/{{a}}", "malformed_expression" },
    { "/{a,b}", "malformed_expression" },
    { "/{+a}", "malformed_expression" },
    { "/{a*}", "malformed_expression" },
    { "/x {id}", "invalid_character" },
    { "/{id}.%zz", "malformed_percent_encoding" },
    { "/{id}%00", "encoded_nul" },
    { "/{id}/{id}", "duplicate_parameter" },
    { "/{id}/{id...}", "duplicate_parameter" },
    { "/{path...}/a", "wildcard_not_last" },
    { "/{path...}/", "wildcard_not_last" },
  }
  for _, case in ipairs(cases) do
    local parsed, reason, detail = template.parse(case[1], "strict")
    self:assert_nil(parsed, case[1])
    self:assert_equal(case[2], reason, case[1])
    self:assert_equal("string", type(detail), case[1])
  end
  self:assert_nil((template.parse(42, "strict")))
end

function T:test_expand_encodes_values_and_keeps_the_declared_shape()
  local parsed = template.parse("/users/{id}/files/{path...}", "strict")
  self:assert_equal("/users/42/files/a/b%20c", template.expand(parsed, { id = 42, path = "a/b c" }))
  self:assert_equal("/users/a%2Fb/files/x", template.expand(parsed, { id = "a/b", path = "x" }))
  self:assert_equal("/", template.expand(template.parse("/", "strict"), {}))
  self:assert_equal("/", template.expand(template.parse("/", "ignore"), {}))
  self:assert_equal("/a/", template.expand(template.parse("/a/", "strict"), {}))
  self:assert_equal("/a%20b", template.expand(template.parse("/a%20b", "strict"), {}))
  self:assert_equal("/a%2Fb", template.expand(template.parse("/a%2Fb", "strict"), {}))
end

function T:test_expand_refuses_what_matching_could_not_read_back()
  local parsed = template.parse("/u/{id}", "strict")
  local wild = template.parse("/f/{path...}", "strict")
  for _, parameters in ipairs({ {}, { id = "" }, { id = "." }, { id = ".." }, { id = true }, { id = 1.5 }, { id = "a\0b" },
    { id = "x", other = "y" } }) do
    refuses(self, function() template.expand(parsed, parameters) end)
  end
  for _, value in ipairs({ "", "/a", "a/", "a//b", "a/./b", "a/../b", "a\0b", 1.5, true }) do
    refuses(self, function() template.expand(wild, { path = value }) end)
  end
end


-- Phase 2 gate review (R-4, R-5, R-6) --------------------------------------------------------------------------------

function T:test_expand_errors_name_expand()
  -- R-4: called directly, `expand` names itself, not `url_for`.
  local parsed = template.parse("/u/{id}", "strict")
  for _, parameters in ipairs({ {}, { id = "" }, { id = 1, extra = 2 }, { id = true } }) do
    local err = self:assert_error(function() template.expand(parsed, parameters) end)
    self:assert_true(err.message:find("^router%.template%.expand: ") ~= nil, err.message)
  end
end

function T:test_expand_accepts_an_integer_for_a_wildcard()
  -- R-6
  self:assert_equal("/f/7", template.expand(template.parse("/f/{path...}", "strict"), { path = 7 }))
  self:assert_equal("/f/-7", template.expand(template.parse("/f/{path...}"), { path = -7 }))
end

function T:test_parse_defaults_to_the_ignore_policy_and_refuses_an_unknown_one()
  -- R-5: the default of `Router` (`ignore`) is the default here too.
  self:assert_equal(1, #template.parse("/a/").segments)
  self:assert_true(template.parse("/a/").slash)
  self:assert_equal(0, #template.parse("/").segments)
  for _, policy in ipairs({ "redirect", 1, true }) do
    refuses(self, function() template.parse("/a", policy) end)
  end
end

return T
