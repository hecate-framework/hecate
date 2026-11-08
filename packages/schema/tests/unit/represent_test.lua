---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible
-- `Schema:represent` (OQ-95): the plain, JSON-ready form of an instance, for a response.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaRepresentTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local protected = dofile(here .. "/../support/protected.lua")
local STEP_CAP_REPRESENT_500 = 5000 -- twice the 2496 steps observed at depth 500

local Status = core.enumeration("RepStatus", { "active", "disabled" })

local function define(name, build, value_kind)
  local C = value_kind and core.value_class(name) or core.class(name)
  function C.schema() return build() end
  function C:init() end
  core.finalise(C)
  return C
end

local function address_class(value_kind)
  return define("RepAddress", function()
    return schema.object({ city = schema.string(), zip = schema.optional(schema.string()) })
  end, value_kind)
end

local function user_class(Address)
  return define("RepUser", function()
    return schema.object({
      name = schema.string(),
      status = schema.enumeration(Status),
      address = schema.of(Address),
      tags = schema.array(schema.string()),
      scores = schema.map(schema.integer()),
      nickname = schema.optional(schema.string()),
      note = schema.nullable(schema.string()),
      limit = schema.default(schema.integer(), 20),
    })
  end)
end

local content = {
  name = "Ada", status = "active", address = { city = "Paris" }, tags = { "a", "b" },
  scores = { x = 1 }, note = json.null,
}

local function round_trip(s, instance)
  local plain = s:represent(instance)
  local text = json.encode(plain)
  local ok, rebuilt = s:build(json.decode(text))
  assert(ok, tostring(rebuilt and rebuilt[1]))
  return plain, text, rebuilt
end

function T:test_ordinary_instance_becomes_a_plain_table()
  local User = user_class(address_class())
  local s = schema.of(User)
  local _, user = s:build(content)
  local plain = s:represent(user)
  self:assert_false(core.is_instance_of(plain, User))
  self:assert_equal("Ada", plain.name)
  self:assert_equal("active", plain.status)
  self:assert_equal("Paris", plain.address.city)
  self:assert_equal(false, core.is_instance_of(plain.address, core.class_of(user.address)))
  self:assert_equal(20, plain.limit) -- filled by the default at build, represented as an attribute
  self:assert_nil(plain.nickname)
  self:assert_equal(json.null, plain.note) -- sent as null: the presence set brings the null back (owner decision 2026-11-08)
end

function T:test_value_instance_becomes_a_plain_table()
  local Address = address_class(true)
  local s = schema.of(Address)
  local _, address = s:build({ city = "Paris", zip = "75001" })
  local plain = s:represent(address)
  self:assert_equal("Paris", plain.city)
  self:assert_equal("75001", plain.zip)
  local round = json.decode(json.encode(plain))
  self:assert_equal("Paris", round.city)
  self:assert_equal("75001", round.zip)
  plain.city = "Lyon" -- plain and writable
  self:assert_equal("Paris", address.city)
end

function T:test_an_undeclared_attribute_never_appears()
  local Address = address_class()
  local s = schema.of(Address)
  local _, address = s:build({ city = "Paris" })
  address.password = "secret"
  local plain = s:represent(address)
  self:assert_nil(plain.password)
  self:assert_nil(json.encode(plain):find("password", 1, true))
  self:assert_nil(json.encode(plain):find("secret", 1, true))
  -- a hand-made table too, and the value class
  self:assert_nil(s:represent({ city = "x", password = "p" }).password)
  local V = address_class(true)
  local _, v = schema.of(V):build({ city = "Paris" })
  self:assert_nil(json.encode(schema.of(V):represent(v)):find("password", 1, true))
end

function T:test_an_undeclared_attribute_of_a_nested_part_is_dropped_too()
  local User = user_class(address_class())
  local s = schema.of(User)
  local _, user = s:build(content)
  user.address.token = "t"
  user.extra = "e"
  local plain = s:represent(user)
  self:assert_nil(plain.address.token)
  self:assert_nil(plain.extra)
end

function T:test_enumeration_member_becomes_its_name()
  local s = schema.enumeration(Status)
  self:assert_equal("disabled", s:represent(Status.disabled))
  self:assert_equal("active", s:represent("active"))
  local err = self:assert_error(function() s:represent({ name = "other" }) end)
  self:assert_equal("hecate.core.ValidationError", err.code)
  self:assert_equal("enum", err.context.violations[1].code)
end

function T:test_round_trip_gives_an_equal_instance()
  for _, value_kind in ipairs({ false, true }) do
    local Address = define("RepAddr" .. tostring(value_kind), function()
      return schema.object({ city = schema.string() })
    end, value_kind)
    local User = define("RepUser" .. tostring(value_kind), function()
      return schema.object({
        status = schema.enumeration(Status), address = schema.of(Address), tags = schema.array(schema.string()),
        scores = schema.map(schema.integer()), nickname = schema.optional(schema.string()),
        note = schema.nullable(schema.string()), limit = schema.default(schema.integer(), 20),
      })
    end, value_kind)
    local s = schema.of(User)
    local _, user = s:build({ status = "disabled", address = { city = "Paris" }, tags = { "a", "b" },
      scores = { x = 1, y = 2 }, note = "n" })
    local plain, _, rebuilt = round_trip(s, user)
    self:assert_equal("disabled", plain.status)
    self:assert_equal("disabled", rebuilt.status.name)
    self:assert_equal("Paris", rebuilt.address.city)
    self:assert_equal(2, #rebuilt.tags)
    self:assert_equal(2, rebuilt.scores.y)
    self:assert_nil(rebuilt.nickname)
    self:assert_equal("n", rebuilt.note)
    self:assert_equal(20, rebuilt.limit)
    -- the second representation is identical to the first
    self:assert_equal(json.encode(plain), json.encode(s:represent(rebuilt)))
  end
end

function T:test_explicit_null_round_trips_on_an_ordinary_instance()
  local Thing = define("RepNullThing", function() return schema.object({ note = schema.nullable(schema.string()) }) end)
  local s = schema.of(Thing)
  local thing = core.allocate(Thing)
  thing.note = json.null
  local _, text, rebuilt = round_trip(s, thing)
  self:assert_equal('{"note":null}', text)
  self:assert_true(schema.sent(rebuilt, "note")) -- sent as null, so the attribute is nil
  self:assert_nil(rebuilt.note)
end

function T:test_null_stays_null_and_nil_is_omitted()
  local Thing = define("RepThing", function()
    return schema.object({ a = schema.nullable(schema.string()), b = schema.optional(schema.string()) })
  end)
  local s = schema.of(Thing)
  local plain = s:represent({ a = json.null })
  self:assert_equal(json.null, plain.a)
  self:assert_nil(plain.b)
  self:assert_equal('{"a":null}', json.encode(plain))
end

function T:test_defaults_are_not_applied()
  local s = schema.object({ n = schema.default(schema.integer(), 5) })
  self:assert_equal("{}", json.encode(s:represent({})))
end

function T:test_empty_array_and_empty_object_keep_their_encoding()
  local s = schema.object({ list = schema.array(schema.string()), map = schema.map(schema.string()),
    obj = schema.object({}) })
  local plain = s:represent({ list = {}, map = {}, obj = {} })
  self:assert_equal('[]', json.encode(plain.list))
  self:assert_equal('{}', json.encode(plain.map))
  self:assert_equal('{}', json.encode(plain.obj))
  self:assert_equal('[]', json.encode(schema.array(schema.integer()):represent({})))
end

function T:test_arrays_keep_their_order()
  local plain = schema.array(schema.integer()):represent({ 3, 1, 2 })
  self:assert_equal("[3,1,2]", json.encode(plain))
end

function T:test_union_picks_the_accepting_alternative()
  local Address = address_class()
  local s = schema.union({ schema.integer(), schema.of(Address) })
  local _, address = schema.of(Address):build({ city = "Paris" })
  address.secret = "s"
  local plain = s:represent(address)
  self:assert_equal("Paris", plain.city)
  self:assert_nil(plain.secret)
  self:assert_equal(7, s:represent(7))
  local err = self:assert_error(function() s:represent("neither") end)
  self:assert_equal("union", err.context.violations[1].code)
end

function T:test_union_of_a_class_that_holds_an_enumeration_member()
  local Box = define("RepBox", function() return schema.object({ status = schema.enumeration(Status) }) end)
  local s = schema.union({ schema.integer(), schema.of(Box) })
  local _, box = schema.of(Box):build({ status = "active" })
  self:assert_equal("active", s:represent(box).status)
end

function T:test_tagged_union_uses_its_tag()
  local s = schema.tagged_union("kind", {
    circle = schema.object({ radius = schema.integer() }),
    square = schema.object({ side = schema.integer() }),
  })
  local plain = s:represent({ kind = "square", side = 2, extra = true })
  self:assert_equal("square", plain.kind)
  self:assert_equal(2, plain.side)
  self:assert_nil(plain.extra)
  local err = self:assert_error(function() s:represent({ kind = "hexagon" }) end)
  self:assert_equal("tagged_union", err.context.violations[1].code)
  self:assert_equal("/kind", err.context.violations[1].path)
end

function T:test_named_any_and_null()
  local named = schema.named("Pair", schema.object({ a = schema.integer() }))
  self:assert_equal("{\"a\":1}", json.encode(named:represent({ a = 1, b = 2 })))
  local any = schema.any()
  local input = { x = { 1, { y = json.null } }, e = json.array({}) }
  local plain = any:represent(input)
  self:assert_equal(json.encode(input), json.encode(plain))
  self:assert_true(plain ~= input and plain.x ~= input.x and plain.x[2] ~= input.x[2])
  self:assert_equal(json.null, schema.null():represent(json.null))
end

function T:test_schema_sent_is_irrelevant()
  local Address = address_class()
  local s = schema.of(Address)
  local _, built = s:build({ city = "Paris", zip = "1" })
  local made = Address()
  made.city, made.zip = "Paris", "1"
  self:assert_equal(json.encode(s:represent(built)), json.encode(s:represent(made)))
end

function T:test_input_unchanged_and_fresh_tables()
  local s = schema.object({ list = schema.array(schema.object({ n = schema.integer() })),
    map = schema.map(schema.array(schema.integer())) })
  local input = { list = { { n = 1 } }, map = { k = { 1, 2 } } }
  local before = json.encode(input)
  local plain = s:represent(input)
  self:assert_equal(before, json.encode(input))
  self:assert_true(plain ~= input)
  self:assert_true(plain.list ~= input.list and plain.list[1] ~= input.list[1])
  self:assert_true(plain.map ~= input.map and plain.map.k ~= input.map.k)
  self:assert_nil(getmetatable(input.list))
end

local function cycle_classes()
  local A, B = core.class("RepCycleA"), core.class("RepCycleB")
  function A.schema() return schema.object({ other = schema.optional(schema.of(B)) }) end
  function B.schema() return schema.object({ other = schema.optional(schema.of(A)) }) end
  core.finalise(A)
  core.finalise(B)
  return A, B
end

function T:test_a_cycle_of_two_classes_ends_with_the_depth_limit()
  local A, B = cycle_classes()
  local a, b = core.allocate(A), core.allocate(B)
  a.other, b.other = b, a
  local err = self:assert_error(function() schema.of(A):represent(a) end)
  -- one step per container visited until the depth guard: bounded by the guard, not by a clock
  self:assert_true(schema._steps() <= 2 * json.DEFAULT_MAX_DEPTH, schema._steps() .. " steps")
  self:assert_equal("hecate.core.ValidationError", err.code)
  local v = err.context.violations[1]
  self:assert_equal("depth_limit", v.code)
  self:assert_equal(json.DEFAULT_MAX_DEPTH, v.context.max_depth)
  self:assert_equal(json.DEFAULT_MAX_DEPTH, select(2, v.path:gsub("/other", "")))
  -- a call after the error is not affected by a stale counter
  self:assert_equal("{}", json.encode(schema.of(A):represent(core.allocate(A))))
end

function T:test_a_hostile_deep_chain_does_not_crash()
  local A = cycle_classes()
  local root = core.allocate(A)
  local node = root
  local _, B = cycle_classes()
  for i = 1, 20000 do -- far above the depth guard of 1000
    local nxt = core.allocate(i % 2 == 0 and A or B)
    node.other = nxt
    node = nxt
  end
  local err = self:assert_error(function() schema.of(A):represent(root) end)
  self:assert_equal("depth_limit", err.context.violations[1].code)
  -- plain nested tables under `any`
  local plain = {}
  local cursor = plain
  for _ = 1, 20000 do cursor.x = {}; cursor = cursor.x end
  local err2 = self:assert_error(function() schema.any():represent(plain) end)
  self:assert_equal("depth_limit", err2.context.violations[1].code)
end

function T:test_the_work_budget_ends_a_representation()
  local ok, err, ok2, err2
  protected.with_fields(schema._limits, { max_steps = 10 }, function()
    ok, err = pcall(function() return schema.array(schema.integer()):represent({ 1, 2, 3 }) end)
    local items = {}
    for i = 1, 50 do items[i] = {} end
    ok2, err2 = pcall(function() return schema.array(schema.object({})):represent(items) end)
  end)
  self:assert_true(ok)
  self:assert_false(ok2)
  self:assert_equal("complexity_limit", err2.context.violations[1].code)
  self:assert_equal("/9", err2.context.violations[1].path)
end

function T:test_a_recursive_union_is_linear()
  local A, B = core.class("RepCostA"), core.class("RepCostB")
  function A.schema()
    return schema.object({ tag = schema.literal("a"), next = schema.optional(schema.union({ schema.of(A), schema.of(B) })) })
  end
  function B.schema()
    return schema.object({ tag = schema.literal("b"), next = schema.optional(schema.union({ schema.of(A), schema.of(B) })) })
  end
  core.finalise(A)
  core.finalise(B)
  local function steps_at(depth)
    local value = { tag = "b" }
    for _ = 2, depth do value = { tag = "a", next = value } end
    self:assert_equal("a", schema.of(A):represent(value).tag)
    return schema._steps()
  end
  local shallow, deep = steps_at(250), steps_at(500)
  -- linear: doubling the depth at most doubles the steps (plus a constant), where an exponential run would square them
  self:assert_true(deep <= 2 * shallow + 10, ("%d steps at depth 500 against %d at depth 250"):format(deep, shallow))
  self:assert_true(deep <= STEP_CAP_REPRESENT_500, deep .. " steps at depth 500")
end

function T:test_a_value_that_is_not_a_table_is_a_clean_error()
  local err = self:assert_error(function() schema.object({}):represent(5) end)
  self:assert_equal("hecate.core.ValidationError", err.code)
  self:assert_equal("type", err.context.violations[1].code)
end

--- Deep equality of decoded content (the encoder does not order keys, so texts are compared by value).
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or a == json.null or b == json.null then return a == b end
  for key, member in pairs(a) do if not same(member, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end

-- Round trip of the content (q1, owner decision 2026-11-08): decode, build, represent, encode gives the canonical input.
local function round_trip_classes()
  local Colour = core.enumeration("RtColour", { "red", "green" })
  local Inner = define("RtInner", function() return schema.object({ city = schema.string() }) end)
  local Outer = define("RtOuter", function()
    return schema.object({
      name = schema.string(),
      nick = schema.nullable(schema.string()), -- required, sent as null
      email = schema.optional(schema.string()), -- absent
      note = schema.optional(schema.nullable(schema.string())), -- sent as null
      limit = schema.default(schema.integer(), 20), -- filled by the default
      colour = schema.enumeration(Colour),
      home = schema.of(Inner),
      spare = schema.nullable(schema.of(Inner)), -- nullable class, sent as null
    })
  end)
  return schema.of(Outer), Outer
end

function T:test_content_round_trips_through_build_and_represent()
  local s = round_trip_classes()
  local text = '{"colour":"green","home":{"city":"Paris"},"limit":20,"name":"Ada","nick":null,"note":null,"spare":null}'
  local ok, instance = s:build(json.decode(text))
  self:assert_true(ok)
  self:assert_nil(instance.nick)
  self:assert_true(same(json.decode(text), json.decode(json.encode(s:represent(instance)))), json.encode(s:represent(instance)))
  -- the default fills an absent attribute, and the result is then a fixed point
  local input = '{"colour":"green","home":{"city":"Paris"},"name":"Ada","nick":null,"note":null,"spare":null}'
  local _, filled = s:build(json.decode(input))
  self:assert_true(same(json.decode(text), json.decode(json.encode(s:represent(filled)))))
  local _, again = s:build(json.decode(text))
  self:assert_true(same(json.decode(text), json.decode(json.encode(s:represent(again)))))
end

function T:test_an_instance_that_was_not_built_omits_a_nil_nullable_attribute()
  local s, Outer = round_trip_classes()
  local instance = core.allocate(Outer)
  instance.name = "Ada"
  instance.colour = "red"
  instance.home = core.allocate(Outer)
  local plain = s:represent(instance)
  self:assert_nil(plain.nick)
  self:assert_nil(plain.spare)
  local sentless = core.allocate(Outer)
  sentless.name, sentless.colour, sentless.home, sentless.nick = "Ada", "red", {}, json.null
  self:assert_equal(json.null, s:represent(sentless).nick) -- a hand-set null stays null
end

function T:test_a_value_class_round_trips_an_explicit_null()
  local Thing = define("RtValueThing", function() return schema.object({ a = schema.nullable(schema.string()), b = schema.optional(schema.string()) }) end, true)
  local s = schema.of(Thing)
  local _, thing = s:build(json.decode('{"a":null}'))
  self:assert_equal('{"a":null}', json.encode(s:represent(thing)))
  local _, sent = s:build(json.decode('{"a":"x","b":"y"}'))
  self:assert_true(same(json.decode('{"a":"x","b":"y"}'), json.decode(json.encode(s:represent(sent)))))
end

return T
