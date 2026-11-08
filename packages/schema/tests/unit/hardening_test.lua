---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible
-- Hardening of the validation core (review of the `schema` item, findings S1 to S4 and s1 to s4): every probe of the
-- security review is reproduced here and bounded by a count of steps, violations or bytes, never by a clock.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaHardeningTest")

local limits = schema._limits

--- Runs `fn` with `limits.max_steps` lowered to `steps`, restoring it even when `fn` raises.
local function with_steps(steps, fn)
  local saved = limits.max_steps
  limits.max_steps = steps
  local ok, err = pcall(fn)
  limits.max_steps = saved
  if not ok then error(err, 0) end
end

local function codes(violations)
  local list = {}
  for i, v in ipairs(violations) do list[i] = v.code end
  return list
end

-- S1: unique_items ---------------------------------------------------------------------------------------------------

function T:test_unique_items_of_many_distinct_integers_is_cheap()
  local s = schema.array(schema.integer(), { unique_items = true })
  local items = {}
  for i = 1, 20000 do items[i] = i end
  with_steps(100000, function() self:assert_true((s:validate(items))) end)
end

function T:test_unique_items_charges_the_work_budget_per_item()
  local s = schema.array(schema.integer(), { unique_items = true })
  local items = {}
  for i = 1, 3000 do items[i] = i end
  with_steps(1000, function()
    local ok, violations = s:validate(items)
    self:assert_false(ok)
    self:assert_equal("complexity_limit", violations[#violations].code)
  end)
end

function T:test_unique_items_charges_the_work_budget_per_table_comparison()
  -- Tables with the same shallow signature are compared pairwise: the comparisons are charged.
  local s = schema.array(schema.array(schema.array(schema.integer())), { unique_items = true })
  local items = {}
  for i = 1, 2000 do items[i] = { { i } } end
  with_steps(100000, function()
    local ok, violations = s:validate(items)
    self:assert_false(ok)
    self:assert_equal("complexity_limit", violations[#violations].code)
  end)
end

function T:test_unique_items_separates_distinct_tables_by_signature()
  local s = schema.array(schema.object({ id = schema.integer() }), { unique_items = true })
  local items = {}
  for i = 1, 3000 do items[i] = { id = i } end
  with_steps(100000, function() self:assert_true((s:validate(items))) end)
end

function T:test_unique_items_scalar_rules()
  local s = schema.array(schema.any(), { unique_items = true })
  self:assert_true((s:validate({ 1, "1", true, "true", json.null, "null", 2 })))
  local ok, violations = s:validate({ 1, 2, 1.0 })
  self:assert_false(ok) -- 1 and 1.0 are equal numbers (OQ-85)
  self:assert_equal("/2", violations[1].path)
  ok, violations = s:validate({ "a", "b", "a" })
  self:assert_false(ok)
  self:assert_equal("unique_items", violations[1].code)
  self:assert_false((s:validate({ true, false, true })))
  self:assert_false((s:validate({ json.null, json.null })))
end

function T:test_unique_items_still_compares_tables_structurally()
  local s = schema.array(schema.any(), { unique_items = true })
  self:assert_false((s:validate({ { a = 1, b = { 1, 2 } }, { b = { 1, 2 }, a = 1 } })))
  self:assert_true((s:validate({ { a = 1, b = { 1, 2 } }, { b = { 1, 3 }, a = 1 } })))
  self:assert_true((s:validate({ { 1 }, { 1, 1 }, {} })))
end

-- S2: pattern and format on unbounded input -------------------------------------------------------------------------

function T:test_pattern_and_format_are_skipped_after_a_max_length_violation()
  local s = schema.string({ max_length = 10, pattern = "^b", format = "email" })
  local ok, violations = s:validate(("a"):rep(100))
  self:assert_false(ok)
  self:assert_equal("max_length", violations[1].code)
  self:assert_equal(1, #violations)
end

function T:test_pattern_is_skipped_after_invalid_utf8()
  local s = schema.string({ min_length = 1, pattern = "^b" })
  local ok, violations = s:validate("\255\254")
  self:assert_false(ok)
  self:assert_equal(1, #violations)
  self:assert_equal("invalid_utf8", violations[1].code)
end

function T:test_a_long_string_never_reaches_the_pattern_without_max_length()
  local s = schema.string({ pattern = "^a*$" })
  self:assert_true((s:validate(("a"):rep(limits.max_pattern_bytes))))
  local ok, violations = s:validate(("a"):rep(limits.max_pattern_bytes + 1))
  self:assert_false(ok)
  self:assert_equal("pattern", violations[1].code)
  self:assert_equal("too_long_for_pattern", violations[1].context.reason)
end

function T:test_a_long_string_never_reaches_the_format_without_max_length()
  local s = schema.string({ format = "email" })
  local ok, violations = s:validate(("a"):rep(limits.max_pattern_bytes + 1) .. "@b.co")
  self:assert_false(ok)
  self:assert_equal("format", violations[1].code)
  self:assert_equal("too_long_for_pattern", violations[1].context.reason)
  self:assert_equal("email", violations[1].context.format)
end

function T:test_a_declared_max_length_bounds_the_pattern_instead_of_the_ceiling()
  local s = schema.string({ max_length = 100000, pattern = "^a*$" })
  self:assert_true((s:validate(("a"):rep(limits.max_pattern_bytes + 1))))
end

-- S3: malformed patterns ---------------------------------------------------------------------------------------------

function T:test_a_malformed_pattern_is_refused_at_declaration()
  for _, pattern in ipairs({ "ab%", "(a", "a)", "[a", "[a%", "%f", "%fa", "%b", "%bx", "%1", "(a)%2", "(%1)", "a(", "%0" }) do
    local err = self:assert_error(function() schema.string({ pattern = pattern }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), pattern)
    self:assert_equal("pattern", err.context.option, pattern)
  end
  local err = self:assert_error(function() schema.string({ pattern = "ab%" }) end)
  self:assert_true(tostring(err.message):find("ends with '%'", 1, true) ~= nil, tostring(err.message))
end

function T:test_well_formed_patterns_are_still_accepted()
  for _, pattern in ipairs({ "^a-$", "%bxy", "%f[%w]%w+", "(a)%1", "()a", "[%]]", "[]]", "[^]a]", "a$b", "%%", "^(%d+)%.(%d+)$", "[a-z]*" }) do
    schema.string({ pattern = pattern })
  end
end

function T:test_a_pattern_that_fails_at_match_time_is_a_violation_not_an_error()
  -- Well formed, but Lua gives up on it: more than 200 nested optional items ("pattern too complex").
  local pattern = ("a?"):rep(300)
  local s = schema.string({ pattern = pattern })
  local subject = ("a"):rep(300)
  local ok, violations = s:validate(subject)
  self:assert_false(ok)
  self:assert_equal("pattern", violations[1].code)
  self:assert_equal("malformed_pattern", violations[1].context.reason)
  ok, violations = s:coerce(subject)
  self:assert_false(ok)
  self:assert_equal("malformed_pattern", violations[1].context.reason)
  ok, violations = schema.object({ s = s }):build({ s = subject })
  self:assert_false(ok)
  self:assert_equal("malformed_pattern", violations[1].context.reason)
end

-- S4: bounded violation lists ----------------------------------------------------------------------------------------

local function keys(count, prefix)
  local t = {}
  for i = 1, count do t[("%s%05d"):format(prefix or "k", i)] = 1 end
  return t
end

function T:test_violations_are_capped_with_a_final_marker()
  local s = schema.object({})
  local ok, violations = s:validate(keys(500))
  self:assert_false(ok)
  self:assert_equal(limits.max_violations + 1, #violations)
  local last = violations[#violations]
  self:assert_equal("too_many_violations", last.code)
  self:assert_equal(limits.max_violations, last.context.max)
  self:assert_equal("additional_properties", violations[1].code)
  self:assert_equal("/k00001", violations[1].path)
end

function T:test_the_cap_is_exact()
  local s = schema.object({})
  local ok, violations = s:validate(keys(limits.max_violations))
  self:assert_false(ok)
  self:assert_equal(limits.max_violations, #violations)
  self:assert_equal("additional_properties", violations[#violations].code)
  ok, violations = s:validate(keys(limits.max_violations + 1))
  self:assert_equal(limits.max_violations + 1, #violations)
  self:assert_equal("too_many_violations", violations[#violations].code)
end

function T:test_validators_stop_descending_once_the_cap_is_hit()
  local s = schema.array(schema.object({ a = schema.integer() }))
  local items = {}
  for i = 1, 1000 do items[i] = {} end
  -- 1000 failing items would cost 1001 steps: the budget must not be what ends the call.
  with_steps(300, function()
    local ok, violations = s:validate(items)
    self:assert_false(ok)
    self:assert_equal("too_many_violations", violations[#violations].code)
    self:assert_equal(limits.max_violations + 1, #violations)
  end)
end

function T:test_coerce_and_build_cap_their_violations()
  local s = schema.array(schema.integer())
  local items = {}
  for i = 1, 1000 do items[i] = "x" end
  local ok, violations = s:coerce(items)
  self:assert_false(ok)
  self:assert_equal(limits.max_violations + 1, #violations)
  self:assert_equal("coercion", violations[1].code)
  self:assert_equal("too_many_violations", violations[#violations].code)
  ok, violations = s:build(items)
  self:assert_false(ok)
  self:assert_equal(limits.max_violations + 1, #violations)
  ok, violations = s:build(items, { coerce = true })
  self:assert_false(ok)
  self:assert_equal(limits.max_violations + 1, #violations)
  self:assert_equal("too_many_violations", violations[#violations].code)
end

function T:test_the_cap_applies_to_maps()
  local s = schema.map(schema.integer())
  local content = {}
  for i = 1, 500 do content[("k%05d"):format(i)] = "x" end
  local _, violations = s:validate(content)
  self:assert_equal(limits.max_violations + 1, #violations)
  local _, coerced = s:coerce(content)
  self:assert_equal(limits.max_violations + 1, #coerced)
end

function T:test_an_echoed_property_name_is_truncated()
  local s = schema.object({})
  local key = ("x"):rep(5000)
  local _, violations = s:validate({ [key] = 1 })
  self:assert_equal("additional_properties", violations[1].code)
  self:assert_true(#violations[1].path <= 1 + 64)
  self:assert_true(#violations[1].context.property <= 64)
  -- a cut inside a multi-byte character backs off to a boundary
  local wide = ("é"):rep(100)
  _, violations = s:validate({ [wide] = 1 })
  self:assert_true(utf8.len(violations[1].context.property) ~= nil)
  self:assert_true(#violations[1].context.property <= 64)
  local map = schema.map(schema.integer())
  _, violations = map:validate({ [key] = "x" })
  self:assert_true(#violations[1].path <= 1 + 64)
end

-- s1: a default is not reachable ------------------------------------------------------------------------------------

function T:test_the_stored_default_is_not_exposed()
  local d = schema.default(schema.array(schema.integer()), { 1, 2 })
  self:assert_nil(d.options.value)
  local s = schema.object({ xs = d })
  local ok, first = s:coerce({})
  self:assert_true(ok)
  first.xs[1] = 99
  local _, second = s:coerce({})
  self:assert_equal(1, second.xs[1])
  local emitted = s:to_json_schema()
  emitted.properties.xs.default[1] = 99
  self:assert_equal(1, s:to_json_schema().properties.xs.default[1])
  local _, built = s:build({})
  built.xs[1] = 99
  local _, again = s:build({})
  self:assert_equal(1, again.xs[1])
end

function T:test_the_value_given_to_default_is_copied()
  local given = { 1, 2 }
  local s = schema.object({ xs = schema.default(schema.array(schema.integer()), given) })
  given[1] = 99
  local _, built = s:coerce({})
  self:assert_equal(1, built.xs[1])
end

-- s2: collisions with class members ---------------------------------------------------------------------------------

local function class_with(name, setup, build)
  local C = core.class(name)
  function C.schema() return build() end
  setup(C)
  core.finalise(C)
  return C
end

function T:test_a_property_named_like_a_method_is_refused()
  local C = class_with("Collides", function(c) function c:save() return true end end,
    function() return schema.object({ save = schema.string() }) end)
  local s = schema.of(C)
  local err = self:assert_error(function() s:validate({ save = "x" }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  local text = tostring(err.message)
  self:assert_true(text:find("Collides", 1, true) ~= nil and text:find("save", 1, true) ~= nil, text)
end

function T:test_a_property_named_like_an_inherited_or_internal_member_is_refused()
  local Base = class_with("CollideBase", function(c) function c:describe() return "x" end end, function() return schema.object({}) end)
  local Child = core.class("CollideChild", Base)
  function Child.schema() return schema.object({ describe = schema.string() }) end
  core.finalise(Child)
  self:assert_error(function() schema.of(Child):validate({}) end, "describe")
  local Dunder = class_with("CollideDunder", function() end, function() return schema.object({ __name = schema.string() }) end)
  self:assert_error(function() schema.of(Dunder):validate({}) end, "__name")
end

function T:test_represent_never_shows_a_prototype_field_or_a_method()
  local C = class_with("Prototyped", function(c) c.role = "admin" end,
    function() return schema.object({ name = schema.string(), role = schema.optional(schema.string()) }) end)
  local s = schema.of(C)
  local _, instance = s:build({ name = "Ada" })
  self:assert_equal("admin", instance.role) -- the prototype, read through the class
  local plain = s:represent(instance)
  self:assert_nil(plain.role)
  self:assert_equal("Ada", plain.name)
  local _, sent = s:build({ name = "Ada", role = "user" })
  self:assert_equal("user", s:represent(sent).role)
end

function T:test_represent_never_shows_a_prototype_field_of_a_value_class()
  local C = core.value_class("PrototypedValue")
  C.role = "admin"
  function C.schema() return schema.object({ name = schema.string(), role = schema.optional(schema.string()) }) end
  core.finalise(C)
  local s = schema.of(C)
  local _, instance = s:build({ name = "Ada" })
  self:assert_equal("admin", instance.role)
  self:assert_nil(s:represent(instance).role)
  local _, sent = s:build({ name = "Ada", role = "user" })
  self:assert_equal("user", s:represent(sent).role)
end

function T:test_represent_skips_a_function_valued_attribute()
  local s = schema.object({ name = schema.string(), run = schema.optional(schema.any()) })
  local plain = s:represent({ name = "Ada", run = function() end })
  self:assert_equal("Ada", plain.name)
  self:assert_nil(plain.run)
  self:assert_equal('{"name":"Ada"}', json.encode(plain))
end

-- s3: boolean false -------------------------------------------------------------------------------------------------

function T:test_false_survives_coercion_in_a_map()
  local ok, result = schema.map(schema.boolean()):coerce({ a = "false", b = "true" })
  self:assert_true(ok)
  self:assert_equal(false, result.a)
  self:assert_equal(true, result.b)
end

function T:test_a_top_level_default_false_is_returned()
  local s = schema.default(schema.boolean(), false)
  local ok, result = s:coerce(nil)
  self:assert_true(ok)
  self:assert_equal(false, result)
  ok, result = s:build(nil)
  self:assert_true(ok)
  self:assert_equal(false, result)
  local o = schema.object({ flag = schema.default(schema.boolean(), false) })
  _, result = o:coerce({})
  self:assert_equal(false, result.flag)
  _, result = o:build({})
  self:assert_equal(false, result.flag)
end

-- s4: email ----------------------------------------------------------------------------------------------------------

function T:test_email_rejects_control_characters_and_long_texts()
  local s = schema.string({ format = "email" })
  self:assert_true((s:validate("a@b.co")))
  for _, text in ipairs({ "a\1@b.co", "a\127@b.co", "a@b.co\0", "a\0@b.co", "a@b\27.co" }) do
    self:assert_false((s:validate(text)), text)
  end
  self:assert_true((s:validate(("a"):rep(249) .. "@b.co"))) -- 254 bytes
  self:assert_false((s:validate(("a"):rep(250) .. "@b.co"))) -- 255 bytes
end

return T
