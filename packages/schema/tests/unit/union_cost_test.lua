---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
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
  local A, B = core.class("CostA"), core.class("CostB")
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

--- Runs `fn`, returns the seconds it took and the memory it left allocated (kilobytes).
local function measure(fn)
  collectgarbage()
  local before = collectgarbage("count")
  local started = os.clock()
  fn()
  local seconds = os.clock() - started
  return seconds, collectgarbage("count") - before
end

local function assert_cheap(self, fn)
  local seconds, kilobytes = measure(fn)
  self:assert_true(seconds < 0.5, "took " .. seconds .. " s")
  self:assert_true(kilobytes < 100 * 1024, "kept " .. kilobytes .. " KB")
end

function T:test_recursive_union_validates_in_linear_work()
  local s = probe()
  for _, depth in ipairs({ 30, 1000 }) do
    local value = content(depth)
    assert_cheap(self, function() self:assert_true((s:validate(value))) end)
  end
end

function T:test_recursive_union_coerces_in_linear_work()
  local s = probe()
  for _, depth in ipairs({ 30, 1000 }) do
    local value = content(depth)
    assert_cheap(self, function() self:assert_true((s:coerce(value))) end)
  end
end

function T:test_recursive_union_builds_in_linear_work()
  local s = probe()
  for _, depth in ipairs({ 30, 1000 }) do
    local value = content(depth)
    assert_cheap(self, function()
      local ok, built = s:build(value)
      self:assert_true(ok)
      self:assert_equal("b", built.tag)
    end)
  end
end

function T:test_failure_deep_in_the_content_is_cheap_and_reported_once_at_the_top()
  local s = probe()
  local value = content(30, "c")
  assert_cheap(self, function()
    local ok, violations = s:validate(value)
    self:assert_false(ok)
    self:assert_equal(1, #violations)
    self:assert_equal("/next", violations[1].path)
    self:assert_equal("union", violations[1].code)
  end)
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

--- Alternatives without a discriminating property: the cost is still exponential, so the budget stops the call.
local function adversarial()
  local A, B = core.class("CostAdvA"), core.class("CostAdvB")
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
  local limits = schema._limits
  local saved = limits.max_steps
  limits.max_steps = 20000
  local s, value = adversarial()
  local ok, violations
  assert_cheap(self, function() ok, violations = s:validate(value) end)
  limits.max_steps = saved
  self:assert_false(ok)
  local found
  for _, v in ipairs(violations) do if v.code == "complexity_limit" then found = v end end
  self:assert_true(found ~= nil, "no complexity_limit violation")
  self:assert_equal(20000, found.context.max_steps)
  self:assert_equal("/", found.path:sub(1, 1))
end

function T:test_work_budget_applies_to_coerce_and_build_and_resets_on_entry()
  local limits = schema._limits
  local saved = limits.max_steps
  limits.max_steps = 20000
  local s, value = adversarial()
  local ok, violations = s:coerce(value)
  self:assert_false(ok)
  self:assert_equal("complexity_limit", violations[#violations].code)
  ok, violations = s:build(value)
  self:assert_false(ok)
  self:assert_equal("complexity_limit", violations[#violations].code)
  -- A small call after an exhausted one is not affected: the counter is reset on entry.
  self:assert_true((schema.object({ a = schema.integer() }):validate({ a = 1 })))
  limits.max_steps = saved
end

function T:test_default_budget_is_one_million_steps()
  self:assert_equal(1000000, schema._limits.max_steps)
end

return T
