---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
-- Seeded property-based differential (review finding S14): for random schemas built with the constructors and random
-- JSON values (derived from the schema, then mutated), `Schema:validate(value)` must agree with the independent checker
-- (`tests/support/conforms.lua`) applied to `to_json_schema()`. The seed is fixed, can be overridden by
-- `HECATE_TEST_SEED`, and is printed by a failure.
--
-- Left out on purpose, and why:
--
-- - `format` and `pattern`: the checker has no engine for them and `format` is an annotation of the emitted document
--   (JSON Schema 2020-12, section 7.2.1); `test_format_is_enforced_by_lua_and_only_an_annotation_when_emitted` pins that
--   asymmetry, and `pattern_test.lua` carries its own differential matcher for `pattern`;
-- - whole floats where an integer is expected: Lua `integer` refuses `1.0`, JSON Schema section 6.1.1 accepts it (OQ-85,
--   point 11, documented in `emit_test.lua`); the generator only produces floats with a fractional part;
-- - fractional `multiple_of`: refused at declaration (OQ-87), so the generator only declares whole divisors;
-- - invalid UTF-8: Lua checks it only where a length is declared, the checker everywhere; the generator writes valid UTF-8.
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaDifferentialTest")

local null = json.null
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local conforms = dofile(here .. "/../support/conforms.lua").conforms
local prng = dofile(here .. "/../support/prng.lua")

local SEED = 0x5EED0001
local SCHEMAS = 320
local VALUES_PER_SCHEMA = 10

local LETTERS = { "a", "b", "c", "x", "\u{e9}", "\u{4e2d}", "\u{1F600}", " " }
local NAMES = { "id", "name", "tags", "kind", "age", "note", "a", "b" }
local WRONG = { "x", 7, 2.5, -1, true, false, null, {}, { 1 }, { a = 1 }, "" }

--- A random `spec`: a plain description from which both the Lua schema and the values are made.
local function gen_spec(rng, depth)
  local leaf = depth <= 0
  local choice = rng.int(1, leaf and 7 or 15)
  if choice == 1 then
    local spec = { kind = "string" }
    if rng.chance(1, 2) then spec.min_length = rng.int(0, 3) end
    if rng.chance(1, 2) then spec.max_length = (spec.min_length or 0) + rng.int(0, 3) end
    return spec
  elseif choice == 2 or choice == 3 then
    local spec = { kind = choice == 2 and "integer" or "number" }
    if rng.chance(1, 2) then spec.minimum = rng.int(-3, 3) end
    if rng.chance(1, 2) then spec.maximum = (spec.minimum or -3) + rng.int(0, 6) end
    if rng.chance(1, 5) then spec.exclusive_minimum = rng.int(-3, 3) end
    if rng.chance(1, 5) then spec.exclusive_maximum = (spec.exclusive_minimum or -3) + rng.int(1, 6) end
    if rng.chance(1, 5) then spec.multiple_of = rng.int(2, 4) end
    return spec
  elseif choice == 4 then
    return { kind = "boolean" }
  elseif choice == 5 then
    return { kind = "literal", value = rng.pick({ "a", "b", 1, 2, true, false, null }) }
  elseif choice == 6 then
    local values, seen = {}, {}
    for _ = 1, rng.int(1, 4) do
      local value = rng.pick({ "a", "b", "c", 1, 2, 3, true, false, null })
      if not seen[value] then seen[value] = true; values[#values + 1] = value end
    end
    return { kind = "enumeration", values = values }
  elseif choice == 7 then
    local pool = { "string", "integer", "boolean" }
    local first = rng.int(1, 3)
    local second = (first + rng.int(0, 1)) % 3 + 1 -- two scalar alternatives of different kinds
    return { kind = "union", alternatives = { { kind = pool[first] }, { kind = pool[second] } } }
  elseif choice == 8 then
    return { kind = "nullable", inner = gen_spec(rng, depth - 1) }
  elseif choice == 9 or choice == 10 then
    local spec = { kind = "object", properties = {}, order = {}, additional = rng.chance(1, 4) }
    local count = rng.int(0, 3)
    for _ = 1, count do
      local name = rng.pick(NAMES)
      if not spec.properties[name] then
        spec.order[#spec.order + 1] = name
        spec.properties[name] = { spec = gen_spec(rng, depth - 1), optional = rng.chance(1, 2) }
      end
    end
    table.sort(spec.order)
    return spec
  elseif choice == 11 or choice == 12 then
    local spec = { kind = "array", item = gen_spec(rng, depth - 1) }
    if rng.chance(1, 3) then spec.min_items = rng.int(0, 2) end
    if rng.chance(1, 3) then spec.max_items = (spec.min_items or 0) + rng.int(0, 3) end
    if rng.chance(1, 3) then spec.unique_items = true end
    return spec
  elseif choice == 13 then
    local spec = { kind = "map", value = gen_spec(rng, depth - 1) }
    if rng.chance(1, 3) then spec.min_properties = rng.int(0, 2) end
    if rng.chance(1, 3) then spec.max_properties = (spec.min_properties or 0) + rng.int(0, 2) end
    return spec
  elseif choice == 14 then
    local variants = { a = {}, b = {} }
    for tag in pairs(variants) do
      local body = { kind = "object", properties = {}, order = {}, additional = rng.chance(1, 4) }
      for _ = 1, rng.int(0, 2) do
        local name = rng.pick({ "x", "y", "z" })
        if not body.properties[name] then
          body.order[#body.order + 1] = name
          body.properties[name] = { spec = gen_spec(rng, 0), optional = rng.chance(1, 2) }
        end
      end
      table.sort(body.order)
      variants[tag] = body
    end
    return { kind = "tagged_union", tag = "kind", variants = variants }
  end
  local inner = gen_spec(rng, depth - 1)
  if inner.kind == "named" then return inner end -- a schema takes one name
  return { kind = "named", inner = inner }
end

--- The Lua schema of a spec. `names` makes every `named` unique within one document.
local function build_schema(spec, names)
  local kind = spec.kind
  if kind == "string" then
    return schema.string({ min_length = spec.min_length, max_length = spec.max_length })
  elseif kind == "integer" or kind == "number" then
    return schema[kind]({ minimum = spec.minimum, maximum = spec.maximum, exclusive_minimum = spec.exclusive_minimum,
      exclusive_maximum = spec.exclusive_maximum, multiple_of = spec.multiple_of })
  elseif kind == "boolean" then
    return schema.boolean()
  elseif kind == "literal" then
    return schema.literal(spec.value)
  elseif kind == "enumeration" then
    return schema.enumeration(spec.values)
  elseif kind == "union" then
    return schema.union({ build_schema(spec.alternatives[1], names), build_schema(spec.alternatives[2], names) })
  elseif kind == "nullable" then
    return schema.nullable(build_schema(spec.inner, names))
  elseif kind == "object" then
    local properties = {}
    for _, name in ipairs(spec.order) do
      local property = spec.properties[name]
      local inner = build_schema(property.spec, names)
      properties[name] = property.optional and schema.optional(inner) or inner
    end
    return schema.object(properties, { additional_properties = spec.additional })
  elseif kind == "array" then
    return schema.array(build_schema(spec.item, names), { min_items = spec.min_items, max_items = spec.max_items,
      unique_items = spec.unique_items })
  elseif kind == "map" then
    return schema.map(build_schema(spec.value, names), { min_properties = spec.min_properties,
      max_properties = spec.max_properties })
  elseif kind == "tagged_union" then
    local variants = {}
    for tag, body in pairs(spec.variants) do variants[tag] = build_schema(body, names) end
    return schema.tagged_union(spec.tag, variants)
  end
  names.count = names.count + 1
  return schema.named("N" .. names.count, build_schema(spec.inner, names))
end

local function gen_text(rng, low, high)
  local parts = {}
  for i = 1, rng.int(low, high) do parts[i] = rng.pick(LETTERS) end
  return table.concat(parts)
end

--- A number near a bound (boundary values), or a small one.
local function gen_number(rng, spec, whole)
  local anchors = {}
  for _, key in ipairs({ "minimum", "maximum", "exclusive_minimum", "exclusive_maximum" }) do
    if spec[key] then anchors[#anchors + 1] = spec[key] end
  end
  local base = #anchors > 0 and rng.pick(anchors) or rng.int(-4, 4)
  local value = base + rng.int(-1, 1)
  if spec.multiple_of and rng.chance(1, 2) then value = rng.int(-3, 3) * spec.multiple_of end
  if not whole and rng.chance(1, 4) then value = value + 0.5 end
  if whole and rng.chance(1, 8) then value = value + 0.5 end -- an integer schema must refuse a fraction
  return value
end

local gen_value

local function gen_object_value(rng, spec, depth)
  local value = {}
  for _, name in ipairs(spec.order) do
    local property = spec.properties[name]
    if not property.optional or rng.chance(2, 3) then value[name] = gen_value(rng, property.spec, depth - 1) end
  end
  return value
end

--- A value derived from the spec, valid most of the time and near a boundary otherwise.
function gen_value(rng, spec, depth)
  local kind = spec.kind
  if kind == "string" then
    local low, high = spec.min_length or 0, spec.max_length or (spec.min_length or 0) + 3
    return gen_text(rng, math.max(0, low - 1), high + 1)
  elseif kind == "integer" then
    return gen_number(rng, spec, true)
  elseif kind == "number" then
    return gen_number(rng, spec, false)
  elseif kind == "boolean" then
    return rng.chance(1, 2)
  elseif kind == "literal" then
    return rng.chance(4, 5) and spec.value or rng.pick({ "a", "b", 1, 2, true, false, null })
  elseif kind == "enumeration" then
    return rng.chance(4, 5) and rng.pick(spec.values) or rng.pick({ "a", "z", 1, 9, true, null })
  elseif kind == "union" then
    return gen_value(rng, rng.pick(spec.alternatives), depth)
  elseif kind == "nullable" then
    return rng.chance(1, 4) and null or gen_value(rng, spec.inner, depth)
  elseif kind == "object" then
    return gen_object_value(rng, spec, depth)
  elseif kind == "array" then
    local low, high = spec.min_items or 0, spec.max_items or (spec.min_items or 0) + 3
    local value = {}
    for i = 1, rng.int(math.max(0, low - 1), high + 1) do
      value[i] = (spec.unique_items and i > 1 and rng.chance(1, 4)) and value[rng.int(1, i - 1)]
        or gen_value(rng, spec.item, depth - 1)
    end
    return value
  elseif kind == "map" then
    local low, high = spec.min_properties or 0, spec.max_properties or (spec.min_properties or 0) + 2
    local value = {}
    for _ = 1, rng.int(math.max(0, low - 1), high + 1) do
      value[rng.pick(NAMES)] = gen_value(rng, spec.value, depth - 1)
    end
    return value
  elseif kind == "tagged_union" then
    local tag = rng.pick({ "a", "b", "a", "b", "c" })
    local variant = spec.variants[tag]
    local value = variant and gen_object_value(rng, variant, depth) or {}
    value[spec.tag] = tag
    return value
  end
  return gen_value(rng, spec.inner, depth)
end

--- A mutation of a value: a wrong type, a removed or an extra member, applied at a random place.
local function mutate(rng, value)
  if type(value) == "table" and value ~= null and rng.chance(3, 4) then
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local copy = {}
    for key, member in pairs(value) do copy[key] = member end
    local roll = rng.int(1, 4)
    if #keys > 0 and roll <= 2 then
      local key = rng.pick(keys)
      copy[key] = mutate(rng, copy[key])
    elseif #keys > 0 and roll == 3 then
      local key = rng.pick(keys)
      if type(key) == "number" then copy[key] = nil; return #keys == key and copy or value end
      copy[key] = nil -- a missing property
    elseif #value == 0 then
      copy.extra = rng.pick(WRONG) -- an extra property
    else
      copy[#value + 1] = rng.pick(WRONG)
    end
    return copy
  end
  return rng.pick(WRONG)
end

function T:test_random_schemas_and_values_agree_with_the_emitted_schema()
  prng.run(SEED, function(rng)
    local pairs_checked, accepted, refused = 0, 0, 0
    for index = 1, SCHEMAS do
      local spec = gen_spec(rng, rng.int(0, 3))
      local s = build_schema(spec, { count = 0 })
      local emitted = s:to_json_schema()
      for _ = 1, VALUES_PER_SCHEMA do
        local value = gen_value(rng, spec, 3)
        if rng.chance(1, 2) then value = mutate(rng, value) end
        local lua_ok = s:validate(value)
        local json_ok = conforms(emitted, value)
        if lua_ok ~= json_ok then
          self:fail(("schema #%d (%s) disagrees: validate=%s, emitted=%s, value=%s\nemitted=%s"):format(index, spec.kind,
            tostring(lua_ok), tostring(json_ok), json.encode(value, { canonical = true }),
            json.encode(emitted, { canonical = true })))
        end
        pairs_checked = pairs_checked + 1
        if lua_ok then accepted = accepted + 1 else refused = refused + 1 end
      end
    end
    self:assert_true(pairs_checked >= 2000, "only " .. pairs_checked .. " pairs")
    -- The generator must produce both verdicts in numbers, or the differential proves nothing.
    self:assert_true(accepted >= pairs_checked // 5, ("accepted %d of %d"):format(accepted, pairs_checked))
    self:assert_true(refused >= pairs_checked // 5, ("refused %d of %d"):format(refused, pairs_checked))
  end)
end

function T:test_the_generator_is_deterministic_for_a_seed()
  local function fingerprint(seed)
    local rng = prng.new(seed)
    local parts = {}
    for _ = 1, 20 do parts[#parts + 1] = json.encode((gen_spec(rng, 3)), { canonical = true }) end
    return table.concat(parts)
  end
  self:assert_equal(fingerprint(7), fingerprint(7))
  self:assert_true(fingerprint(7) ~= fingerprint(8))
end

function T:test_a_failure_carries_the_seed()
  local err = self:assert_error(function() prng.run(42, function() error({ harness_failure = "boom" }, 0) end) end)
  self:assert_true(err.harness_failure:find("HECATE_TEST_SEED=", 1, true) ~= nil)
  self:assert_true(err.harness_failure:find("boom", 1, true) ~= nil)
end

function T:test_format_is_enforced_by_lua_and_only_an_annotation_when_emitted()
  -- The emitted document carries `format` (an annotation in 2020-12, section 7.2.1) and the checker ignores it, so the
  -- two verdicts differ on a malformed value: this is why `format` is excluded from the differential above.
  local s = schema.string({ format = "uuid" })
  local emitted = s:to_json_schema()
  self:assert_equal("uuid", emitted.format)
  self:assert_equal("string", emitted.type)
  local ok, violations = s:validate("not-a-uuid")
  self:assert_false(ok)
  self:assert_equal("format", violations[1].code)
  self:assert_true(conforms(emitted, "not-a-uuid"), "the checker must ignore format")
  self:assert_true((s:validate("123e4567-e89b-12d3-a456-426614174000")))
  self:assert_true(conforms(emitted, "123e4567-e89b-12d3-a456-426614174000"))
end

return T
