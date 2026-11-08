---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible
-- Algorithmic cost of a recursive `union` of container alternatives (OQ-91): the work of a call is bounded in the
-- depth of the content (fail-fast alternatives, discriminating properties first) and, whatever the schema, by a work
-- budget that ends the call with a `complexity_limit` violation.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaUnionCostTest")

--- Two classes A and B, a literal tag and an optional `next` that is a union of both (the probe of OQ-91).
local function probe()
  local A, B = core.class("CostA", nil, { implements = { schema.Representable } }), core.class("CostB", nil, { implements = { schema.Representable } })
  function A.schema()
    return schema.object({ tag = schema.literal("a"),
      next = schema.optional(schema.union({ schema.of(A), schema.of(B) })) })
  end
  function B.schema()
    return schema.object({ tag = schema.literal("b"),
      next = schema.optional(schema.union({ schema.of(A), schema.of(B) })) })
  end
  core.finalise(A)
  core.finalise(B)
  return schema.of(B)
end

--- Content of `depth` levels of B; the innermost level has the tag `last`.
local function content(depth, last)
  local value = { tag = last or "b" }
  for _ = 2, depth do value = { tag = "b", next = value } end
  return value
end

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local protected = dofile(here .. "/../support/protected.lua")

--- Runs `fn` and returns the steps of the work budget it spent (`schema._steps()` after the call) and the memory it left
--- allocated, in kilobytes. No clock: the cost is the deterministic count of steps (container visits and alternatives
--- tried), the same on every platform and every runner.
local function measure(fn)
  collectgarbage()
  local before = collectgarbage("count")
  fn()
  local steps = schema._steps()
  return steps, collectgarbage("count") - before
end

local function verbose(label, steps, kilobytes)
  if os.getenv("HECATE_TEST_VERBOSE") then io.stderr:write(("# union_cost %s: %d steps, %.0f KB\n"):format(label, steps, kilobytes)) end
end

--- The memory left allocated (garbage not yet collected included) is only a gross backstop: ten times what was observed
--- on the reference run (about 60 MB at 2000 levels, mostly the path strings), far below what an exponential run would use.
local RETAINED_KB_BACKSTOP = 600 * 1024

--- Steps spent by `run` on content of 30, 1000 and 2000 levels (2000 is beyond the depth guard of validation: the call
--- fails, and the work must still grow in proportion). Asserts that the steps per level stay within a constant factor of
--- those of the shallow case, which is what linear work means; a quadratic or exponential run breaks the ratio at once.
local function assert_linear(self, label, run)
  local per_level = {}
  for _, depth in ipairs({ 30, 1000, 2000 }) do
    local steps, kilobytes = measure(function() run(depth) end)
    verbose(label .. " depth " .. depth, steps, kilobytes)
    self:assert_true(kilobytes < RETAINED_KB_BACKSTOP, ("%s depth %d kept %.0f KB"):format(label, depth, kilobytes))
    per_level[depth] = steps / depth
  end
  for _, depth in ipairs({ 1000, 2000 }) do
    local ratio = per_level[depth] / per_level[30]
    self:assert_true(ratio <= 1.5 and ratio >= 1 / 1.5,
      ("%s: steps per level %.2f at depth 30, %.2f at depth %d (ratio %.2f)"):format(label, per_level[30], per_level[depth], depth, ratio))
  end
end

function T:test_recursive_union_validates_in_linear_work()
  local s = probe()
  assert_linear(self, "validate", function(depth)
    local ok = s:validate(content(depth))
    self:assert_equal(depth <= 1000, ok) -- beyond the depth guard the call fails
  end)
end

function T:test_recursive_union_coerces_in_linear_work()
  local s = probe()
  assert_linear(self, "coerce", function(depth)
    local ok = s:coerce(content(depth))
    self:assert_equal(depth <= 1000, ok)
  end)
end

function T:test_recursive_union_builds_in_linear_work()
  local s = probe()
  assert_linear(self, "build", function(depth)
    local ok, built = s:build(content(depth))
    self:assert_equal(depth <= 1000, ok)
    if ok then self:assert_equal("b", built.tag) end
  end)
end

local FAILURE_DEEP_STEPS = 462 -- twice the 231 steps observed (a failure at depth 30 of the probe)

function T:test_failure_deep_in_the_content_is_cheap_and_reported_once_at_the_top()
  local s = probe()
  local value = content(30, "c")
  local steps, kilobytes = measure(function()
    local ok, violations = s:validate(value)
    self:assert_false(ok)
    self:assert_equal(1, #violations)
    self:assert_equal("/next", violations[1].path)
    self:assert_equal("union", violations[1].code)
  end)
  verbose("failure deep", steps, kilobytes)
  self:assert_true(steps <= FAILURE_DEEP_STEPS, steps .. " steps")
end

function T:test_the_top_union_carries_the_violations_of_every_alternative()
  local s = schema.union({ schema.object({ tag = schema.literal("a") }), schema.object({ tag = schema.literal("b") }) })
  local ok, violations = s:validate({ tag = "c" })
  self:assert_false(ok)
  self:assert_equal(1, #violations)
  local alternatives = violations[1].context.alternatives
  self:assert_equal(2, #alternatives)
  self:assert_equal("literal", alternatives[1][1].code)
  self:assert_equal("/tag", alternatives[2][1].path)
end

function T:test_a_union_nested_in_a_failed_alternative_has_no_alternatives_of_its_own()
  local inner = schema.union({ schema.string(), schema.integer() })
  local s = schema.union({ schema.object({ x = inner }), schema.object({ y = schema.string() }) })
  local ok, violations = s:validate({ x = true })
  self:assert_false(ok)
  local first = violations[1].context.alternatives[1][1]
  self:assert_equal("/x", first.path)
  self:assert_equal("union", first.code)
  self:assert_equal(0, #first.context.alternatives)
end

--- Alternatives without a discriminating property. The memoisation makes this linear, so the budget is lowered by the
--- tests below to show that it still ends a call that spends more than it allows.
local function adversarial()
  local A, B = core.class("CostAdvA", nil, { implements = { schema.Representable } }), core.class("CostAdvB", nil, { implements = { schema.Representable } })
  local of_a, of_b = schema.of(A), schema.of(B) -- shared, so that each class resolves once
  local function body()
    return schema.object({ value = schema.optional(schema.string()),
      next = schema.optional(schema.union({ of_a, of_b })) })
  end
  function A.schema() return body() end
  function B.schema() return body() end
  core.finalise(A)
  core.finalise(B)
  local s = schema.object({ next = schema.union({ of_a, of_b }) })
  -- Every level accepts either class, and the innermost value is invalid: nothing prunes the search.
  local value = { value = 1 }
  for _ = 1, 40 do value = { next = value } end
  return s, { next = value }
end

function T:test_work_budget_ends_the_call_with_complexity_limit()
  local s, value = adversarial()
  local ok, violations, steps
  protected.with_fields(schema._limits, { max_steps = 100 }, function()
    ok, violations = s:validate(value)
    steps = schema._steps()
  end)
  self:assert_false(ok)
  -- The budget is the bound: the call stops at it (one step more is counted when it is found spent), whatever the schema.
  self:assert_true(steps <= 101, steps .. " steps for a budget of 100")
  local found
  for _, v in ipairs(violations) do if v.code == "complexity_limit" then found = v end end
  self:assert_true(found ~= nil, "no complexity_limit violation")
  self:assert_equal(100, found.context.max_steps)
  self:assert_equal("/", found.path:sub(1, 1))
end

function T:test_work_budget_applies_to_coerce_and_build_and_resets_on_entry()
  local s, value = adversarial()
  protected.with_fields(schema._limits, { max_steps = 100 }, function()
    local ok, violations = s:coerce(value)
    self:assert_false(ok)
    self:assert_equal("complexity_limit", violations[#violations].code)
    ok, violations = s:build(value)
    self:assert_false(ok)
    self:assert_equal("complexity_limit", violations[#violations].code)
    -- A small call after an exhausted one is not affected: the counter is reset on entry.
    self:assert_true((schema.object({ a = schema.integer() }):validate({ a = 1 })))
    self:assert_true(schema._steps() <= 2, schema._steps() .. " steps for one object")
  end)
end

function T:test_a_failing_assertion_does_not_leak_a_lowered_budget()
  local saved = schema._limits.max_steps
  local ok = pcall(protected.with_fields, schema._limits, { max_steps = 5 }, function() error("boom") end)
  self:assert_false(ok)
  self:assert_equal(saved, schema._limits.max_steps)
end

function T:test_default_budget_is_one_million_steps()
  self:assert_equal(1000000, schema._limits.max_steps)
end

--- Two classes of identical shape P and Q, `next = optional(union(P, Q))` at every level and no discriminating literal:
--- the probe of the memoisation (OQ-91). The innermost value is invalid.
local function twins(depth)
  local P, Q = core.class("CostTwinP", nil, { implements = { schema.Representable } }), core.class("CostTwinQ", nil, { implements = { schema.Representable } })
  local of_p, of_q = schema.of(P), schema.of(Q)
  local function body()
    return schema.object({ value = schema.optional(schema.string()),
      next = schema.optional(schema.union({ of_p, of_q })) })
  end
  function P.schema() return body() end
  function Q.schema() return body() end
  core.finalise(P)
  core.finalise(Q)
  local value = { value = 1 }
  for _ = 2, depth do value = { next = value } end
  return of_p, value
end

local DEPTH_COMPARED = 30 -- 12 when comparing with the revision before the memoisation (30 reaches its budget)

--- Steps per `run` of the twins, observed on the reference run; the caps are twice that (the adversarial case needs at most
--- this many steps with the memoisation, and the budget of one million is far above them).
local TWINS_STEP_CAP = {
  validate = { [30] = 462, [1000] = 15982 },
  coerce = { [30] = 1148, [1000] = 39948 },
  build = { [30] = 462, [1000] = 15982 },
}

local function assert_steps_of_twins(self, method)
  local per_level = {}
  for _, depth in ipairs({ 30, 1000 }) do
    local s, value = twins(depth)
    local violations
    local steps, kilobytes = measure(function() violations = select(2, s[method](s, value)) end)
    verbose("twins " .. method .. " depth " .. depth, steps, kilobytes)
    for _, v in ipairs(violations) do self:assert_true(v.code ~= "complexity_limit", "reached the work budget") end
    self:assert_true(#violations > 0)
    self:assert_true(steps <= TWINS_STEP_CAP[method][depth], ("%s depth %d: %d steps, cap %d"):format(method, depth, steps, TWINS_STEP_CAP[method][depth]))
    self:assert_true(kilobytes < RETAINED_KB_BACKSTOP, ("kept %.0f KB"):format(kilobytes))
    per_level[depth] = steps / depth
  end
  local ratio = per_level[1000] / per_level[30]
  self:assert_true(ratio <= 1.5 and ratio >= 1 / 1.5, ("%s: steps per level %.2f then %.2f"):format(method, per_level[30], per_level[1000]))
end

function T:test_identical_alternatives_with_an_invalid_innermost_value_are_linear_for_validate()
  assert_steps_of_twins(self, "validate")
end

function T:test_identical_alternatives_with_an_invalid_innermost_value_are_linear_for_coerce()
  assert_steps_of_twins(self, "coerce")
end

function T:test_identical_alternatives_with_an_invalid_innermost_value_are_linear_for_build()
  assert_steps_of_twins(self, "build")
end

function T:test_memoisation_keeps_violations_paths_and_top_level_alternatives()
  local s, value = twins(DEPTH_COMPARED)
  for _, run in ipairs({ function() return s:validate(value) end, function() return s:coerce(value) end,
    function() return s:build(value) end }) do
    local ok, violations = run()
    self:assert_false(ok)
    -- The top level is the class itself (no union above it): its violation is the union of `next`, at depth 1.
    self:assert_equal(1, #violations)
    self:assert_equal("union", violations[1].code)
    self:assert_equal("/next", violations[1].path)
    local alternatives = violations[1].context.alternatives
    self:assert_equal(2, #alternatives)
    for _, list in ipairs(alternatives) do
      self:assert_equal(1, #list)
      self:assert_equal("/next/next", list[1].path)
      self:assert_equal("union", list[1].code)
      self:assert_equal(0, #list[1].context.alternatives)
    end
  end
end

function T:test_memoisation_does_not_change_the_result_for_shared_nodes()
  -- The same table reached twice: both visits answer alike, and a later call starts without a cache.
  local u = schema.union({ schema.object({ a = schema.integer() }), schema.object({ b = schema.string() }) })
  local s = schema.object({ x = u, y = u })
  local shared = { a = 1 }
  self:assert_true((s:validate({ x = shared, y = shared })))
  local bad = { a = "no" }
  local ok, violations = s:validate({ x = bad, y = bad })
  self:assert_false(ok)
  self:assert_equal(2, #violations)
  self:assert_equal("/x", violations[1].path)
  self:assert_equal("/y", violations[2].path)
  bad.a = 2
  self:assert_true((s:validate({ x = bad, y = bad })), "a stale cache from an earlier call")
end

--- The coerce results of a failed union as they were before b67dfde (verified against that revision): the value is left
--- as it is, the union is reported at its own path with the violations of every alternative.
function T:test_failed_coerce_of_a_plain_union_keeps_its_shape()
  local s = schema.object({ x = schema.union({ schema.integer(), schema.boolean() }) })
  local ok, violations = s:coerce({ x = "maybe" })
  self:assert_equal(false, ok)
  self:assert_equal(1, #violations)
  self:assert_equal("union", violations[1].code)
  self:assert_equal("/x", violations[1].path)
  self:assert_equal(2, #violations[1].context.alternatives)
  local objects = schema.union({ schema.object({ n = schema.integer() }), schema.object({ m = schema.boolean() }) })
  ok, violations = objects:coerce({ n = "x", m = "y" })
  self:assert_equal(false, ok)
  self:assert_equal(1, #violations)
  self:assert_equal("union", violations[1].code)
  self:assert_equal("", violations[1].path)
  self:assert_equal(2, #violations[1].context.alternatives)
end

function T:test_failed_coerce_of_a_union_with_literal_tags_keeps_the_union_shape()
  local s = schema.union({
    schema.object({ kind = schema.literal("a"), n = schema.integer() }),
    schema.object({ kind = schema.literal("b"), m = schema.boolean() }),
  })
  local ok, violations = s:coerce({ kind = "b", m = "maybe" })
  self:assert_equal(false, ok)
  -- Same as before b67dfde: the value is left as it is and the union is reported (the old code found the same).
  self:assert_equal(1, #violations)
  self:assert_equal("union", violations[1].code)
  self:assert_equal("", violations[1].path)
  self:assert_equal(2, #violations[1].context.alternatives)
end

function T:test_failed_coerce_of_a_tagged_union_reports_the_selected_variant()
  local s = schema.tagged_union("kind", {
    a = schema.object({ n = schema.integer() }),
    b = schema.object({ m = schema.boolean() }),
  })
  local ok, violations = s:coerce({ kind = "b", m = "maybe" })
  self:assert_equal(false, ok)
  self:assert_equal(1, #violations)
  -- OQ-88 point 2: the violations are those of the selected variant.
  self:assert_equal("coercion", violations[1].code)
  self:assert_equal("/m", violations[1].path)
end

return T
