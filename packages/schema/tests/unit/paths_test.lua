---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
-- The paths of violations (P1 of the review): the validators, coercers and representers do not build a path string for a
-- visit, they keep a stack of reference tokens and join it where a violation is recorded. The paths must stay exactly
-- the JSON Pointers (RFC 6901) of the node, whatever was visited before: nested objects, arrays (0-based indices), maps,
-- unions, tagged unions, tokens that need escaping (`~` and `/`), a long key cut to the echo maximum, siblings that fail
-- after a sibling that descended deep, and the order of the violations of undeclared properties.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaPathsTest")

local function paths_of(violations)
  local list = {}
  for i, v in ipairs(violations) do list[i] = v.path .. " " .. v.code end
  return list
end

local function assert_paths(self, expected, violations)
  self:assert_equal(table.concat(expected, "\n"), table.concat(paths_of(violations), "\n"))
end

local Leaf = schema.integer()
local tagged = schema.tagged_union("kind", {
  one = schema.object({ n = schema.integer() }),
  ["t/w~o"] = schema.object({ s = schema.string() }),
})
local alternatives = schema.union({
  schema.object({ k = schema.literal("a"), v = schema.integer() }),
  schema.array(schema.string()),
})
local tree = schema.object({
  ["a/b"] = schema.array(schema.map(schema.object({
    ["~x"] = Leaf,
    ["y/z"] = tagged,
    u = alternatives,
  }))),
  plain = schema.string(),
  deep = schema.object({ one = schema.object({ two = schema.array(schema.integer()) }) }),
})

function T:test_nested_object_array_map_paths_are_escaped_and_zero_based()
  local ok, violations = tree:validate({
    ["a/b"] = {
      { ["k/1"] = { ["~x"] = "no", ["y/z"] = { kind = "one", n = "x" }, u = { k = "a", v = "s" } } },
      { ["k~2"] = { ["~x"] = 1, ["y/z"] = { kind = "t/w~o", s = 1 }, u = { 1 } } },
    },
    plain = 7,
    deep = { one = { two = { 1, "b", 3, "d" } } },
  })
  self:assert_false(ok)
  assert_paths(self, {
    "/a~1b/0/k~11/u union",
    "/a~1b/0/k~11/y~1z/n type",
    "/a~1b/0/k~11/~0x type",
    "/a~1b/1/k~02/u union",
    "/a~1b/1/k~02/y~1z/s type",
    "/deep/one/two/1 type",
    "/deep/one/two/3 type",
    "/plain type",
  }, violations)
end

function T:test_a_sibling_after_a_deep_descent_reports_its_own_path()
  local ok, violations = tree:validate({ ["a/b"] = {}, plain = 1, deep = { one = { two = { "x" } } } })
  self:assert_false(ok)
  assert_paths(self, { "/deep/one/two/0 type", "/plain type" }, violations)
  local s = schema.object({ a = schema.object({ b = schema.array(schema.object({ c = schema.integer() })) }), z = schema.integer() })
  local _, found = s:validate({ a = { b = { { c = "x" }, { c = 1 }, { c = "y" } } }, z = "q" })
  assert_paths(self, { "/a/b/0/c type", "/a/b/2/c type", "/z type" }, found)
end

function T:test_required_and_undeclared_properties_have_escaped_paths()
  local s = schema.object({ ["p/q"] = schema.object({ ["r~s"] = schema.integer() }) })
  local _, violations = s:validate({ ["p/q"] = { other = 1, ["w/~"] = 2 } })
  assert_paths(self, { "/p~1q/r~0s required", "/p~1q/other additional_properties", "/p~1q/w~1~0 additional_properties" },
    violations)
  local _, tagged_violations = tagged:validate({ kind = "t/w~o" })
  assert_paths(self, { "/s required" }, tagged_violations)
  local _, unknown = schema.object({ x = tagged }):validate({ x = { kind = "zzz" } })
  assert_paths(self, { "/x/kind tagged_union" }, unknown)
  local _, missing = schema.object({ x = tagged }):validate({ x = {} })
  assert_paths(self, { "/x/kind required" }, missing)
end

function T:test_a_long_key_is_cut_in_its_path()
  local key = ("k"):rep(70)
  local _, violations = schema.map(schema.integer()):validate({ [key] = "x" })
  assert_paths(self, { "/" .. ("k"):rep(64) .. " type" }, violations)
  local _, extra = schema.object({}):validate({ [key] = 1 })
  assert_paths(self, { "/" .. ("k"):rep(64) .. " additional_properties" }, extra)
end

function T:test_items_of_an_array_of_arrays_and_unique_items()
  local s = schema.array(schema.array(schema.integer(), { unique_items = true }))
  local _, violations = s:validate({ { 1, 2 }, { 3, 3 }, { "x" } })
  assert_paths(self, { "/1/1 unique_items", "/2/0 type" }, violations)
end

function T:test_coercion_paths()
  local s = schema.object({
    ["a/b"] = schema.array(schema.integer()),
    m = schema.map(schema.boolean()),
    n = schema.object({ ["~"] = schema.number() }),
  })
  local ok, violations = s:coerce({ ["a/b"] = { "1", "x", "3", "y" }, m = { ["k/1"] = "maybe" }, n = { ["~"] = "z" } })
  self:assert_false(ok)
  assert_paths(self, { "/a~1b/1 coercion", "/a~1b/3 coercion", "/m/k~11 coercion", "/n/~0 coercion" }, violations)
  local good, converted = s:coerce({ ["a/b"] = "1,2", m = { x = "true" }, n = { ["~"] = "1.5" } })
  self:assert_true(good)
  self:assert_equal(2, converted["a/b"][2])
  local _, built = s:build({ ["a/b"] = { "1", "x" }, m = {}, n = { ["~"] = "1" } }, { coerce = true })
  assert_paths(self, { "/a~1b/1 coercion" }, built)
end

function T:test_build_paths()
  local _, violations = tree:build({ ["a/b"] = { { z = { ["y/z"] = { kind = "one", n = 1.5 } } } }, plain = "p",
    deep = { one = { two = {} } } })
  assert_paths(self, { "/a~1b/0/z/u required", "/a~1b/0/z/y~1z/n type", "/a~1b/0/z/~0x required" }, violations)
end

function T:test_represent_stops_at_the_path_of_the_node()
  local function stop(value, s)
    local ok, err = pcall(function() return s:represent(value) end)
    self:assert_false(ok)
    self:assert_not_nil(err.context)
    return err.context.violations[1]
  end
  local s = schema.object({ ["a/b"] = schema.array(schema.map(tagged)), plain = schema.string() })
  local v = stop({ ["a/b"] = { { ["k~"] = { kind = "one", n = 1 } }, { ["k/"] = { kind = "nope" } } } }, s)
  self:assert_equal("/a~1b/1/k~1/kind", v.path)
  self:assert_equal("tagged_union", v.code)
  local list = schema.array(alternatives)
  local u = stop({ { k = "a", v = 1 }, { 5 } }, list)
  self:assert_equal("/1", u.path)
  self:assert_equal("union", u.code)
  local plain = stop({ "x" }, schema.array(schema.array(schema.integer())))
  self:assert_equal("/0", plain.path)
  self:assert_equal("type", plain.code)
end

function T:test_depth_limit_path_and_any_copy()
  local s = schema.array(schema.any())
  local value, node = {}, nil
  node = value
  for _ = 1, 1010 do local child = {}; node[1] = child; node = child end
  local ok, err = pcall(function() return s:represent({ value }) end)
  self:assert_false(ok)
  local v = err.context.violations[1]
  self:assert_equal("depth_limit", v.code)
  self:assert_equal("/0" .. ("/1"):rep(999), v.path) -- the Lua keys of the nested tables are 1
end

function T:test_undeclared_properties_come_in_byte_order_whatever_the_insertion_order()
  local s = schema.object({ id = schema.integer() })
  local names = { "zeta", "alpha", "Beta", "a~b", "a/b", "é", "a", "_x", "10", "9" }
  local expected
  for round = 1, 6 do
    local value = { id = 1 }
    for i = 1, #names do value[names[(i * round) % #names + 1]] = true end
    for i = 1, #names do value[names[i]] = true end
    local _, violations = s:validate(value)
    local got = {}
    for i, v in ipairs(violations) do got[i] = v.path end
    expected = expected or got
    self:assert_equal(table.concat(expected, " "), table.concat(got, " "))
  end
  local sorted = { table.unpack(names) }
  table.sort(sorted)
  local escaped = {}
  for i, name in ipairs(sorted) do escaped[i] = "/" .. name:gsub("~", "~0"):gsub("/", "~1") end
  self:assert_equal(table.concat(escaped, " "), table.concat(expected, " "))
end

function T:test_undeclared_properties_of_a_nested_union_failure_are_ordered_too()
  local s = schema.union({ schema.object({ a = schema.integer() }), schema.object({ b = schema.integer() }) })
  local value = { a = 1, y = 1, x = 1, w = 1, z = 1, v = 1 }
  local _, violations = s:validate(value)
  local detail = violations[1].context.alternatives[1]
  local got = {}
  for i, v in ipairs(detail) do got[i] = v.path end
  self:assert_equal("/v /w /x /y /z", table.concat(got, " "))
end

function T:test_map_coercion_violations_come_in_key_order()
  local s = schema.map(schema.integer())
  local value = {}
  for _, key in ipairs({ "q", "b", "z", "a", "m", "c" }) do value[key] = "x" end
  local first
  for _ = 1, 5 do
    local ok, violations = s:coerce(value)
    self:assert_false(ok)
    local got = {}
    for i, v in ipairs(violations) do got[i] = v.path end
    first = first or table.concat(got, " ")
    self:assert_equal(first, table.concat(got, " "))
  end
  self:assert_equal("/a /b /c /m /q /z", first)
end

function T:test_the_cap_keeps_the_first_undeclared_properties_in_byte_order()
  local s = schema.object({ id = schema.integer() })
  for _, method in ipairs({ "validate", "coerce", "build" }) do
    for _ = 1, 3 do
      local value = { id = 1 }
      for i = 1, 150 do value[("key%03d"):format((i * 7) % 150)] = true end
      local ok, violations = s[method](s, value)
      self:assert_false(ok)
      self:assert_equal(101, #violations)
      self:assert_equal("/key000", violations[1].path)
      self:assert_equal("/key099", violations[100].path)
      self:assert_equal("too_many_violations", violations[101].code)
    end
  end
end

function T:test_json_null_and_empty_path_are_unchanged()
  local _, root = schema.integer():validate("x")
  assert_paths(self, { " type" }, root)
  local _, nulls = schema.object({ n = schema.integer() }):validate({ n = json.null })
  assert_paths(self, { "/n type" }, nulls)
end

return T
