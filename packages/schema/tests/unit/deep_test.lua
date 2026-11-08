---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
-- Hostile depth (OQ-50): incoming content is a tree whose depth `json.decode` bounds (`max_depth`, at most 1000);
-- a hand-built table is not bounded, so the compiled validators carry their own guard.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaDeepTest")

local MAX = 1000

--- The schema of a class `Chain` whose instances hold an optional `next` instance (self-reference by `schema.of`).
local function chain()
  local Chain = core.class("Chain")
  function Chain.schema()
    return schema.object({ value = schema.optional(schema.integer()), next = schema.optional(schema.of(Chain)) })
  end
  core.finalise(Chain)
  return schema.of(Chain)
end

--- JSON text of `depth` nested objects; the innermost holds `"value":"x"` when `bad` is set.
local function text_of_depth(depth, bad)
  return ('{"next":'):rep(depth - 1) .. (bad and '{"value":"x"}' or "{}") .. ("}"):rep(depth - 1)
end

function T:test_decoded_maximum_depth_validates_coerces_and_builds()
  local s = chain()
  local value = json.decode(text_of_depth(MAX))
  self:assert_true((s:validate(value)))
  self:assert_true((s:coerce(value)))
  local ok, built = s:build(value)
  self:assert_true(ok)
  local node, depth = built, 0
  while node ~= nil do depth = depth + 1; node = node.next end
  self:assert_equal(MAX, depth)
end

function T:test_decoded_maximum_depth_reports_the_deepest_path()
  local ok, violations = chain():validate(json.decode(text_of_depth(MAX, true)))
  self:assert_false(ok)
  self:assert_equal(("/next"):rep(MAX - 1) .. "/value", violations[1].path)
  self:assert_equal("type", violations[1].code)
end

function T:test_decoded_maximum_depth_through_arrays_and_named()
  local Tree = core.class("Tree")
  function Tree.schema() return schema.object({ children = schema.array(schema.of(Tree)) }) end
  core.finalise(Tree)
  local s = schema.of(Tree)
  local levels = MAX // 2 - 1
  local value = json.decode(('{"children":['):rep(levels) .. '{"children":[]}' .. (']}'):rep(levels))
  self:assert_true((s:validate(value)))
  self:assert_true((s:coerce(value)))
  self:assert_true((s:build(value)))
end

function T:test_content_nested_beyond_the_decoder_maximum_never_reaches_schema()
  local ok, err = pcall(json.decode, text_of_depth(MAX + 1))
  self:assert_false(ok)
  self:assert_equal("depth_limit", err.context.reason)
end

--- A table nested `depth` levels, built iteratively.
local function deep_table(depth)
  local root = {}
  local node = root
  for _ = 1, depth do
    local child = {}
    node.next = child
    node = child
  end
  return root
end

function T:test_hand_built_table_far_deeper_than_the_maximum_is_a_violation()
  local s = chain()
  local value = deep_table(20000) -- far above the depth guard of 1000
  local expected_path = ("/next"):rep(MAX)
  for _, method in ipairs({ "validate", "coerce", "build" }) do
    local ok, accepted, violations = pcall(s[method], s, value)
    self:assert_true(ok, method .. " raised: " .. tostring(accepted))
    self:assert_false(accepted)
    self:assert_equal("depth_limit", violations[1].code)
    self:assert_equal(expected_path, violations[1].path)
  end
end

return T
