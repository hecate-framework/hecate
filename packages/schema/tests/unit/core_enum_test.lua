---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaCoreEnumerationTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local conforms = dofile(here .. "/../support/conforms.lua").conforms

local function status() return core.enumeration("Status", { "active", "disabled", "pending" }) end

function T:test_accepts_exactly_the_names()
  local s = schema.enumeration(status())
  for _, name in ipairs({ "active", "disabled", "pending" }) do self:assert_true(s:validate(name)) end
  for _, bad in ipairs({ "Active", "", "other", 1, true, json.null, {}, { "active" } }) do
    self:assert_false((s:validate(bad)), tostring(bad))
  end
end

function T:test_a_member_object_is_not_json_and_is_refused()
  local Status = status()
  local s = schema.enumeration(Status)
  self:assert_false((s:validate(Status.active)))
end

function T:test_violation_is_the_one_of_the_literal_set()
  local s = schema.enumeration(status())
  local literal = schema.enumeration({ "active", "disabled", "pending" })
  local _, violations = s:validate("nope")
  local _, expected = literal:validate("nope")
  self:assert_equal(expected[1].code, violations[1].code)
  self:assert_equal("enum", violations[1].code)
  self:assert_equal("", violations[1].path)
  self:assert_equal(3, #violations[1].context.values)
  self:assert_equal("active", violations[1].context.values[1])
  self:assert_equal("pending", violations[1].context.values[3])
end

function T:test_coerces_a_text_to_the_name()
  local s = schema.enumeration(status())
  local ok, value = s:coerce("disabled")
  self:assert_true(ok)
  self:assert_equal("disabled", value)
  local failed, violations = s:coerce("nope")
  self:assert_false(failed)
  self:assert_equal("enum", violations[1].code)
end

function T:test_emits_type_and_enum_and_agrees_with_the_independent_checker()
  local s = schema.enumeration(status())
  local emitted = s:to_json_schema()
  self:assert_equal("string", emitted.type)
  self:assert_equal(3, #emitted.enum)
  self:assert_equal("active", emitted.enum[1])
  local values = { "active", "disabled", "pending", "Active", "", "x", 1, 1.5, true, json.null, {}, { "active" }, { a = 1 } }
  for i, value in ipairs(values) do
    self:assert_equal(s:validate(value), conforms(emitted, value), "value #" .. i)
  end
end

function T:test_the_literal_set_emission_is_unchanged()
  local emitted = schema.enumeration({ "a", "b" }):to_json_schema()
  self:assert_nil(emitted.type)
  self:assert_equal(2, #emitted.enum)
end

function T:test_emission_round_trips_through_json()
  local emitted = schema.enumeration(status()):to_json_schema()
  local decoded = json.decode(json.encode(emitted, { canonical = true }))
  self:assert_equal("string", decoded.type)
  self:assert_equal("disabled", decoded.enum[2])
end

function T:test_an_empty_declaration_is_refused()
  local err = self:assert_error(function() schema.enumeration({}) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
  -- A `core.enumeration` is never empty (`core` refuses it), so the schema cannot receive one.
  self:assert_error(function() core.enumeration("Empty", {}) end)
  self:assert_error(function() schema.enumeration(nil) end)
  self:assert_error(function() schema.enumeration("Status") end)
end

function T:test_members_are_read_once_and_a_finalised_enumeration_cannot_change()
  local Status = status()
  local s = schema.enumeration(Status)
  local err = self:assert_error(function() Status.extra = "x" end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_false((s:validate("extra")))
  -- Nothing the caller holds changes the schema.
  local members = s:members()
  members[1] = "tampered"
  self:assert_equal("active", s:members()[1])
  self:assert_true(s:validate("active"))
  self:assert_equal("string", s:to_json_schema().type)
end

function T:test_the_schema_is_an_immutable_value()
  local s = schema.enumeration(status())
  local err = self:assert_error(function() s.kind = "string" end)
  self:assert_equal("hecate.core.ConformanceError", err.code)
  self:assert_equal("enumeration", s.kind)
end

function T:test_inside_object_array_map_and_union()
  local s = schema.object({
    state = schema.enumeration(status()),
    history = schema.array(schema.enumeration(status())),
    by_name = schema.map(schema.enumeration(status())),
    either = schema.union({ schema.enumeration(status()), schema.integer() }),
  })
  self:assert_true(s:validate({ state = "active", history = { "pending" }, by_name = { a = "disabled" }, either = 3 }))
  self:assert_true(s:validate({ state = "active", history = {}, by_name = {}, either = "pending" }))
  local ok, violations = s:validate({ state = "x", history = { "active", "y" }, by_name = { a = "z" }, either = "w" })
  self:assert_false(ok)
  local paths = {}
  for _, v in ipairs(violations) do paths[v.path] = v.code end
  self:assert_equal("enum", paths["/state"])
  self:assert_equal("enum", paths["/history/1"])
  self:assert_equal("enum", paths["/by_name/a"] or "enum")
  self:assert_not_nil(paths["/by_name/a"])
  local emitted = s:to_json_schema()
  for _, value in ipairs({
    { state = "active", history = { "pending" }, by_name = { a = "disabled" }, either = 3 },
    { state = "x", history = {}, by_name = {}, either = 3 },
    { state = "active", history = { "y" }, by_name = {}, either = 3 },
    { state = "active", history = {}, by_name = { a = "z" }, either = 3 },
    { state = "active", history = {}, by_name = {}, either = "w" },
  }) do
    self:assert_equal(s:validate(value), conforms(emitted, value))
  end
end

function T:test_default_takes_the_name_and_builds_the_member()
  local Status = status()
  local s = schema.object({ state = schema.default(schema.enumeration(Status), "pending") })
  self:assert_true(s:validate({}))
  self:assert_equal("pending", s:to_json_schema().properties.state.default)
  local ok, built = s:build({})
  self:assert_true(ok)
  self:assert_true(built.state == Status.pending)
  self:assert_error(function() schema.default(schema.enumeration(Status), "nope") end)
  self:assert_error(function() schema.default(schema.enumeration(Status), Status.active) end)
end

function T:test_build_gives_the_member_for_class_bound_parts()
  local Status = status()
  local Account = core.value_class("Account")
  function Account.schema()
    return schema.object({ state = schema.enumeration(Status), past = schema.optional(schema.array(schema.enumeration(Status))) })
  end
  function Account:init(a) self.state = a.state end
  core.finalise(Account)
  local ok, account = schema.of(Account):build({ state = "disabled", past = { "active", "pending" } })
  self:assert_true(ok)
  self:assert_true(account.state == Status.disabled)
  self:assert_equal(2, Status.disabled.ordinal)
  self:assert_true(account.past[1] == Status.active)
  self:assert_true(account.past[2] == Status.pending)
  local cok, coerced = schema.of(Account):build({ state = "pending" }, { coerce = true })
  self:assert_true(cok)
  self:assert_true(coerced.state == Status.pending)
  local bad, violations = schema.of(Account):build({ state = "nope" })
  self:assert_false(bad)
  self:assert_equal("/state", violations[1].path)
end

function T:test_build_in_a_union_and_nullable()
  local Status = status()
  local u = schema.union({ schema.enumeration(Status), schema.integer() })
  local _, a = u:build("active")
  self:assert_true(a == Status.active)
  local _, n = u:build(4)
  self:assert_equal(4, n)
  local nullable = schema.nullable(schema.enumeration(Status))
  local _, nothing = nullable:build(json.null)
  self:assert_equal(json.null, nothing)
  local _, member = nullable:build("pending")
  self:assert_true(member == Status.pending)
end

function T:test_two_enumerations_with_the_same_names_stay_apart_in_build()
  local A = core.enumeration("A", { "x", "y" })
  local B = core.enumeration("B", { "x", "y" })
  local _, a = schema.enumeration(A):build("x")
  local _, b = schema.enumeration(B):build("x")
  self:assert_true(a == A.x)
  self:assert_true(b == B.x)
  self:assert_false(a == b)
end

function T:test_named_is_the_opt_in_definition()
  local Status = status()
  local inline = schema.object({ a = schema.enumeration(Status), b = schema.enumeration(Status) }):to_json_schema()
  self:assert_nil(inline["$defs"])
  self:assert_equal("string", inline.properties.a.type)
  local named = schema.object({
    a = schema.named("Status", schema.enumeration(Status)),
    b = schema.named("Status", schema.enumeration(Status)),
  }):to_json_schema()
  self:assert_equal("#/$defs/Status", named.properties.a["$ref"])
  self:assert_equal("string", named["$defs"].Status.type)
  self:assert_equal(3, #named["$defs"].Status.enum)
  local _, built = schema.named("Status", schema.enumeration(Status)):build("active")
  self:assert_true(built == Status.active)
end

return T
