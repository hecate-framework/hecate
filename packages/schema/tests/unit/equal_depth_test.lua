---@diagnostic disable: need-check-nil, param-type-mismatch
-- OQ-99 (2): the structural equality behind `unique_items` is bounded at the shared depth limit. A hand-built table
-- nested far deeper than decoded content can be is DIFFERENT from another one, never a Lua stack overflow.
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaEqualDepthTest")

local LIMIT = json.DEFAULT_MAX_DEPTH
local STEP_CAP = 5000000 -- VM instructions; the walk stops at LIMIT levels, so a few thousand are enough

--- A table nested `levels` deep, built iteratively (a recursive builder would overflow itself).
local function nested(levels, leaf)
  local value = leaf
  for _ = 1, levels do value = { value } end
  return value
end

--- Runs `fn` and fails when it spends more than STEP_CAP VM instructions.
local function bounded(self, fn)
  local spent = false
  debug.sethook(function() spent = true; error("step cap exceeded", 0) end, "", STEP_CAP)
  local ok, err = pcall(fn)
  debug.sethook()
  self:assert_false(spent, "the comparison is bounded")
  if not ok then error(err, 0) end
end

local unique = schema.array(schema.any(), { unique_items = true })

function T:test_unique_items_of_two_very_deep_tables_gives_a_clean_verdict()
  local items = { nested(20000, 1), nested(20000, 1) }
  bounded(self, function()
    local ok, violations = unique:validate(items)
    self:assert_true(ok) -- deeper than the bound: different, so unique
    self:assert_nil(violations)
  end)
end

function T:test_unique_items_of_the_same_very_deep_table_twice_is_a_duplicate()
  local deep = nested(20000, 1)
  bounded(self, function()
    local ok, violations = unique:validate({ deep, deep })
    self:assert_false(ok)
    self:assert_equal("unique_items", violations[1].code)
  end)
end

function T:test_unique_items_stays_exact_just_below_the_bound()
  local below = LIMIT - 2 -- the items themselves are one level inside the array
  local ok, violations = unique:validate({ nested(below, 1), nested(below, 1) })
  self:assert_false(ok)
  self:assert_equal("unique_items", violations[1].code)
  self:assert_true((unique:validate({ nested(below, 1), nested(below, 2) })))
end

function T:test_unique_items_treats_tables_deeper_than_the_bound_as_different()
  local ok = unique:validate({ nested(LIMIT + 5, 1), nested(LIMIT + 5, 1) })
  self:assert_true(ok)
end

function T:test_ordinary_nested_values_compare_equal()
  local ok, violations = unique:validate({ { a = { 1, { b = "x" } } }, { a = { 1, { b = "x" } } } })
  self:assert_false(ok)
  self:assert_equal("unique_items", violations[1].code)
  self:assert_true((unique:validate({ { a = { 1, { b = "x" } } }, { a = { 1, { b = "y" } } } })))
end

function T:test_enum_and_const_give_a_clean_verdict_on_a_very_deep_table()
  local deep = nested(20000, 1)
  bounded(self, function()
    for _, s in ipairs({ schema.enumeration({ "a", 1 }), schema.literal("a"), schema.literal(json.null) }) do
      local ok, violations = s:validate(deep)
      self:assert_false(ok)
      self:assert_equal(1, #violations)
    end
  end)
end

function T:test_emission_of_two_named_schemas_is_unaffected()
  local a = schema.named("Same", schema.string())
  local doc = schema.object({ x = a, y = schema.named("Same", schema.string()) }):to_json_schema()
  self:assert_equal("string", doc["$defs"].Same.type)
end

return T
