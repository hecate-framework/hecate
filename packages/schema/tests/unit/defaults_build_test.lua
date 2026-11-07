---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaDefaultsBuildTest")

local function class_of(name, build)
  local C = core.class(name)
  function C.schema() return build() end
  core.finalise(C)
  return C
end

local function settings()
  return schema.object({
    name = schema.string(),
    role = schema.default(schema.string(), "member"),
    tags = schema.default(schema.array(schema.string()), { "a" }),
    note = schema.default(schema.nullable(schema.string()), "none"),
  })
end

function T:test_post_and_put_apply_the_default()
  for _, method in ipairs({ "POST", "PUT" }) do
    local ok, built = settings():build({ name = "x" }, { method = method })
    self:assert_true(ok)
    self:assert_equal("member", built.role)
    self:assert_equal("a", built.tags[1])
    self:assert_equal("none", built.note)
  end
  local _, built = settings():build({ name = "x" })
  self:assert_equal("member", built.role) -- POST/PUT is the default method
end

function T:test_patch_never_applies_a_default_and_stays_relaxed()
  local ok, built = settings():build({}, { method = "PATCH" })
  self:assert_true(ok)
  self:assert_nil(built.name)
  self:assert_nil(built.role)
  self:assert_nil(built.tags)
  self:assert_nil(built.note)
  local ok2, built2 = settings():build({ role = "admin" }, { method = "PATCH" })
  self:assert_true(ok2)
  self:assert_equal("admin", built2.role)
  self:assert_false((settings():build({ name = 1 }, { method = "PATCH" })))
end

function T:test_patch_applies_no_default_in_nested_content()
  local s = schema.object({ inner = schema.optional(settings()) })
  self:assert_false((s:build({ inner = {} }, { method = "PATCH" })))
  local ok2, built2 = s:build({ inner = { name = "n" } }, { method = "PATCH" })
  self:assert_true(ok2)
  self:assert_nil(built2.inner.role)
end

function T:test_explicit_null_stays_null()
  local ok, built = settings():build({ name = "x", note = json.null })
  self:assert_true(ok)
  self:assert_equal(json.null, built.note)
  self:assert_false((settings():build({ name = "x", role = json.null }))) -- not nullable: still a violation
end

function T:test_sent_is_false_for_a_defaulted_attribute()
  local C = class_of("Account", settings)
  local ok, account = schema.of(C):build({ name = "x", role = "admin" })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(account, C))
  self:assert_equal("admin", account.role)
  self:assert_true(schema.sent(account, "role"))
  self:assert_equal("a", account.tags[1])
  self:assert_false(schema.sent(account, "tags"))
  self:assert_equal("none", account.note)
  self:assert_false(schema.sent(account, "note"))
  local _, nulled = schema.of(C):build({ name = "x", note = json.null })
  self:assert_nil(nulled.note)
  self:assert_true(schema.sent(nulled, "note"))
end

function T:test_nested_objects_arrays_and_maps()
  local item = schema.object({ n = schema.integer(), flag = schema.default(schema.boolean(), true) })
  local s = schema.object({
    one = item,
    list = schema.array(item),
    dict = schema.map(item),
  })
  local ok, built = s:build({ one = { n = 1 }, list = { { n = 2 }, { n = 3, flag = false } }, dict = { k = { n = 4 } } })
  self:assert_true(ok)
  self:assert_true(built.one.flag)
  self:assert_true(built.list[1].flag)
  self:assert_false(built.list[2].flag)
  self:assert_true(built.dict.k.flag)
end

function T:test_default_of_a_class_bound_part_is_an_instance()
  local Leaf = class_of("DefaultLeaf", function() return schema.object({ x = schema.default(schema.integer(), 7) }) end)
  local s = schema.object({ leaf = schema.default(schema.of(Leaf), json.object({})) })
  local ok, built = s:build({})
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(built.leaf, Leaf))
  self:assert_equal(7, built.leaf.x)
end

function T:test_default_is_a_fresh_copy_and_input_is_unchanged()
  local s = schema.object({ tags = schema.default(schema.array(schema.string()), { "a" }) })
  local input = {}
  local _, first = s:build(input)
  local _, second = s:build(input)
  self:assert_nil(next(input))
  self:assert_true(first.tags ~= second.tags)
  first.tags[1] = "changed"
  first.tags[2] = "more"
  local _, third = s:build({})
  self:assert_equal("a", third.tags[1])
  self:assert_nil(third.tags[2])
  self:assert_equal("a", second.tags[1])
end

function T:test_union_and_tagged_union_members_with_defaults()
  local u = schema.union({
    schema.object({ kind = schema.literal("a"), v = schema.default(schema.integer(), 1) }),
    schema.object({ kind = schema.literal("b"), w = schema.default(schema.string(), "w") }),
  })
  local ok, a = u:build({ kind = "a" })
  self:assert_true(ok)
  self:assert_equal(1, a.v)
  local _, b = u:build({ kind = "b" })
  self:assert_equal("w", b.w)
  local t = schema.tagged_union("type", {
    cat = schema.object({ lives = schema.default(schema.integer(), 9) }),
    dog = schema.object({ good = schema.default(schema.boolean(), true) }),
  })
  local _, cat = t:build({ type = "cat" })
  self:assert_equal(9, cat.lives)
  local _, dog = t:build({ type = "dog" }, { method = "PUT" })
  self:assert_true(dog.good)
  local _, patched = t:build({ type = "cat" }, { method = "PATCH" })
  self:assert_nil(patched.lives)
end

function T:test_top_level_default_replaces_an_absent_value()
  local s = schema.default(schema.integer(), 5)
  local ok, value = s:build(nil)
  self:assert_true(ok)
  self:assert_equal(5, value)
  self:assert_false((s:build(nil, { method = "PATCH" })))
  local _, given = s:build(8)
  self:assert_equal(8, given)
end

function T:test_validate_stays_pure()
  local s = settings()
  local input = { name = "x" }
  self:assert_true((s:validate(input)))
  self:assert_nil(input.role)
end

return T
