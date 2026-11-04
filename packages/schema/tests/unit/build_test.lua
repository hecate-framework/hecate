---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaBuildTest")

--- A class `name` whose schema() is built by `build`.
local function class_of(name, build)
  local C = core.class(name)
  function C.schema() return build() end
  core.finalise(C)
  return C
end

local function keys(t)
  local list = {}
  for key in pairs(t) do
    if type(key) == "string" then list[#list + 1] = key end -- the presence set has a private, non-string key
  end
  table.sort(list)
  return list
end

local function user_class()
  return class_of("User", function()
    return schema.object({
      name = schema.string(),
      nick = schema.optional(schema.nullable(schema.string())),
      age = schema.optional(schema.integer()),
    })
  end)
end

function T:test_interface_requires_a_class_level_schema_function()
  local HasSchema = core.interface("HasSchema", { "schema" })
  local Bad = core.class("Bad", nil, { implements = { HasSchema } })
  self:assert_false(pcall(core.finalise, Bad))
  local Good = core.class("Good", nil, { implements = { HasSchema } })
  function Good.schema() return schema.object({}) end
  self:assert_true(pcall(core.finalise, Good))
end

function T:test_build_gives_an_instance_of_the_class()
  local User = user_class()
  local ok, user = schema.of(User):build({ name = "ada", age = 36 })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(user, User))
  self:assert_equal("ada", user.name)
  self:assert_equal(36, user.age)
  self:assert_nil(user.nick)
end

function T:test_absent_required_attribute_fails_for_post_and_put()
  local s = schema.of(user_class())
  for _, method in ipairs({ "POST", "PUT" }) do
    local ok, violations = s:build({ age = 3 }, { method = method })
    self:assert_false(ok)
    self:assert_equal("/name", violations[1].path)
    self:assert_equal("required", violations[1].code)
  end
  self:assert_false((s:build({ age = 3 }))) -- strict by default
end

function T:test_failure_returns_violations_with_paths()
  local ok, violations = schema.of(user_class()):build({ name = "a", age = "x" })
  self:assert_false(ok)
  self:assert_equal("/age", violations[1].path)
end

function T:test_presence_set_tells_null_from_absent_without_polluting()
  local User = user_class()
  local ok, user = schema.of(User):build({ name = "ada", nick = json.null })
  self:assert_true(ok)
  self:assert_nil(user.nick)
  self:assert_true(schema.sent(user, "nick"))
  self:assert_true(schema.sent(user, "name"))
  self:assert_false(schema.sent(user, "age"))
  self:assert_equal("name", table.concat(keys(user), ","))
  self:assert_false(schema.sent(User(), "name")) -- not built: nothing was sent
end

function T:test_patch_relaxes_required_attributes()
  local s = schema.of(user_class())
  local ok, user = s:build({ age = 3 }, { method = "PATCH" })
  self:assert_true(ok)
  self:assert_nil(user.name)
  self:assert_false(schema.sent(user, "name"))
  self:assert_true(schema.sent(user, "age"))
  ok = s:build({ nick = json.null }, { method = "PATCH" })
  self:assert_true(ok) -- nilable: cleared
end

function T:test_patch_explicit_null_fails_unless_nilable()
  local s = schema.of(user_class())
  local ok, violations = s:build({ name = json.null }, { method = "PATCH" })
  self:assert_false(ok)
  self:assert_equal("/name", violations[1].path)
  self:assert_equal("type", violations[1].code)
  self:assert_false((s:build({ age = "x" }, { method = "PATCH" })))
end

function T:test_patch_does_not_loosen_the_strict_validator()
  local s = schema.of(user_class())
  s:build({}, { method = "PATCH" })
  self:assert_false((s:validate({})))
end

function T:test_unknown_method_is_refused()
  local s = schema.of(user_class())
  ---@diagnostic disable-next-line: assign-type-mismatch
  self:assert_false(pcall(s.build, s, {}, { method = "GET" }))
  self:assert_false(pcall(s.build, s, {}, { verb = "POST" }))
end

function T:test_self_reference_builds_nested_instances()
  local Node
  Node = class_of("Node", function()
    return schema.object({ label = schema.string(), children = schema.array(schema.of(Node)) })
  end)
  local ok, root = schema.of(Node):build({ label = "a", children = { { label = "b", children = {} } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(root.children[1], Node))
  self:assert_equal("b", root.children[1].label)
  self:assert_true(schema.sent(root.children[1], "label"))
  local bad, violations = schema.of(Node):build({ label = "a", children = { { children = {} } } })
  self:assert_false(bad)
  self:assert_equal("/children/0/label", violations[1].path)
end

function T:test_mutual_pair_builds()
  local A, B
  A = class_of("MA", function() return schema.object({ b = schema.optional(schema.of(B)) }) end)
  B = class_of("MB", function() return schema.object({ a = schema.optional(schema.of(A)), n = schema.optional(schema.integer()) }) end)
  local ok, a = schema.of(A):build({ b = { a = { b = { n = 1 } } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(a.b, B))
  self:assert_true(core.is_instance_of(a.b.a, A))
  self:assert_equal(1, a.b.a.b.n)
end

function T:test_cycle_of_three_classes_builds()
  local A, B, C
  A = class_of("CA", function() return schema.object({ b = schema.optional(schema.of(B)) }) end)
  B = class_of("CB", function() return schema.object({ c = schema.optional(schema.of(C)) }) end)
  C = class_of("CC", function() return schema.object({ a = schema.optional(schema.of(A)), v = schema.optional(schema.string()) }) end)
  local ok, a = schema.of(A):build({ b = { c = { a = { b = { c = { v = "deep" } } } } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(a.b.c.a.b.c, C))
  self:assert_equal("deep", a.b.c.a.b.c.v)
  self:assert_false((schema.of(A):build({ b = { c = { a = { b = { c = { v = 1 } } } } } })))
end

function T:test_build_in_unions_and_plain_objects()
  local Leaf = class_of("Leaf", function() return schema.object({ x = schema.integer() }) end)
  local s = schema.object({ item = schema.union({ schema.of(Leaf), schema.string() }), tags = schema.map(schema.of(Leaf)) })
  local ok, built = s:build({ item = { x = 1 }, tags = { k = { x = 2 } } })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(built.item, Leaf))
  self:assert_true(core.is_instance_of(built.tags.k, Leaf))
  local _, text = s:build({ item = "s", tags = {} })
  self:assert_equal("s", text.item)
end

return T
