-- The official JSON Schema test suite (https://github.com/json-schema-org/JSON-Schema-Test-Suite, MIT, pinned in
-- tests/external.lua, downloaded by `lua tools/run.lua fetch-fixtures schema`), dialect 2020-12, the files of
-- `tests/draft2020-12` (the `optional/` directory is not run: `format` is an annotation in 2020-12, section 7.2.1).
--
-- Three checks per group, over the groups whose schema uses only the supported keywords:
--
-- 1. The independent checker of the emission (tests/support/conforms.lua) evaluates the OFFICIAL schema and must give
--    the official `valid` of every case: this validates the oracle that `emit_test.lua` relies on.
-- 2. When the official schema can be written mechanically as a Hecate schema (translate below), `Schema:validate` must
--    give the official `valid`: Lua validation agrees with the official expectation.
-- 3. For those same schemas, the emitted JSON Schema, evaluated by the checker, must give the same verdict as
--    `Schema:validate` on the official data: the invariant "the emitted JSON Schema validates exactly what Lua
--    validation accepts", on official data.
--
-- Not covered, and why (nothing is skipped silently: a group is skipped for the reason of the first unsupported
-- keyword in GROUP_SKIPS or TRANSLATION_SKIPS, and the counts are printed when a check fails):
--
-- - keywords that Hecate cannot declare or the checker cannot read (GROUP_SKIPS): `allOf`, `not`, `if`, `contains`,
--   `prefixItems`, `patternProperties`, `unevaluated*`, `dependent*`, `propertyNames`, `$id`, `$anchor`,
--   `$dynamicRef`, remote references, ...;
-- - `pattern` (an ECMA-262 expression: the checker has no engine and a Hecate `pattern` is a Lua pattern, OQ-85) and
--   `format` (an annotation unless a vocabulary asserts it);
-- - for check 2 and 3, schemas that no Hecate schema expresses (TRANSLATION_SKIPS): untyped keywords (`minimum`
--   without `type`, which a Hecate type cannot ignore), `oneOf` (a Hecate `union` is `anyOf`), type arrays, boolean
--   schemas, recursive references, constants that are arrays or objects (a Hecate `literal` is a scalar), whole
--   floats for `integer` (the documented gap of OQ-85 point 11: Lua `integer` refuses `1.0`, JSON Schema accepts it;
--   it is counted per case as `gap: 1.0`, only where Lua says invalid, the suite says valid, and a whole float sits at a
--   position where an integer type, a `const` or an `enum` applies, in the data or as the constant);
--   the checker's binary-float `multipleOf` with a fractional divisor is counted per case as a gap, only where the checker
--   disagrees with the suite and a number meets such a divisor;
-- - the number of cases per gap, per run and per skip reason is pinned below (MAX_GAPS, EXPECTED_RUN, EXPECTED_SKIPS).
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaJsonSchemaSuiteTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local dir = here .. "/../../../../.hecate/fixtures/schema/JSON-Schema-Test-Suite/tests/draft2020-12/"
local support = dofile(here .. "/../support/conforms.lua")
local null = json.null

-- Locally the suite is optional (no network, no download yet); in CI a missing suite is a failure (the mechanism
-- of the corpus of `json`).
local function present(self)
  local file = io.open(dir .. "type.json", "rb")
  if file then
    file:close()
    return true
  end
  local message = "the JSON Schema test suite is missing (lua tools/run.lua fetch-fixtures schema)"
  if os.getenv("CI") then self:fail(message) end
  io.stderr:write("# skipped: " .. message .. "\n")
  return false
end

local FILES = {
  "additionalProperties", "allOf", "anchor", "anyOf", "boolean_schema", "const", "contains", "content", "default",
  "defs", "dependentRequired", "dependentSchemas", "dynamicRef", "enum", "exclusiveMaximum", "exclusiveMinimum",
  "format", "if-then-else", "infinite-loop-detection", "items", "maxContains", "maxItems", "maxLength", "maxProperties",
  "maximum", "minContains", "minItems", "minLength", "minProperties", "minimum", "multipleOf", "not", "oneOf",
  "pattern", "patternProperties", "prefixItems", "properties", "propertyNames", "ref", "refRemote", "required", "type",
  "unevaluatedItems", "unevaluatedProperties", "uniqueItems", "vocabulary",
}

-- Keywords whose subschemas are read, per position.
local SCHEMA_MAPS = { properties = true, ["$defs"] = true }
local SCHEMA_LISTS = { oneOf = true, anyOf = true }
local SCHEMA_ONES = { items = true, additionalProperties = true }
-- Keywords with a value that is data, or an annotation.
local DATA = {
  type = true, enum = true, const = true, minimum = true, maximum = true, exclusiveMinimum = true,
  exclusiveMaximum = true, multipleOf = true, minLength = true, maxLength = true, minItems = true, maxItems = true,
  uniqueItems = true, required = true, minProperties = true, maxProperties = true, default = true, description = true,
  title = true, ["$comment"] = true, ["$schema"] = true, ["$ref"] = true,
}

-- The reason a group is not run, by first unsupported keyword.
local GROUP_SKIPS = {
  allOf = "Hecate declares no allOf (an intersection of schemas)",
  ["not"] = "Hecate declares no not",
  ["if"] = "Hecate declares no if/then/else", ["then"] = "Hecate declares no if/then/else",
  ["else"] = "Hecate declares no if/then/else",
  contains = "Hecate declares no contains", minContains = "Hecate declares no contains",
  maxContains = "Hecate declares no contains",
  prefixItems = "Hecate declares no tuple (prefixItems)",
  patternProperties = "Hecate declares no patternProperties",
  propertyNames = "Hecate declares no propertyNames",
  unevaluatedItems = "Hecate declares no unevaluated keywords", unevaluatedProperties = "Hecate declares no unevaluated keywords",
  dependentRequired = "Hecate declares no dependent keywords", dependentSchemas = "Hecate declares no dependent keywords",
  dependencies = "Hecate declares no dependent keywords",
  ["$id"] = "identifiers and base URIs are not emitted (one document, local references)",
  ["$anchor"] = "anchors are not emitted", ["$dynamicRef"] = "dynamic references are not emitted",
  ["$dynamicAnchor"] = "dynamic references are not emitted", ["$vocabulary"] = "vocabularies are out of scope",
  pattern = "pattern: ECMA-262 expression (the checker has no engine, a Hecate pattern is a Lua pattern, OQ-85)",
  format = "format is an annotation in 2020-12 (section 7.2.1)",
  contentEncoding = "content keywords are annotations", contentMediaType = "content keywords are annotations",
  contentSchema = "content keywords are annotations",
}

--- The keys of a decoded object in a fixed order, so that the reason a group is skipped never depends on `pairs`.
local function sorted_keys(node)
  local keys = {}
  for key in pairs(node) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function skip_reason_of_group(node, root)
  if type(node) == "boolean" then return nil end
  if type(node) ~= "table" then return "a schema that is not an object" end
  local keys = {}
  for key in pairs(node) do keys[#keys + 1] = key end
  table.sort(keys) -- a deterministic first reason
  for _, key in ipairs(keys) do
    local value = node[key]
    if GROUP_SKIPS[key] then return GROUP_SKIPS[key] end
    if key == "$ref" then
      if type(value) ~= "string" or not value:find("^#") then return "remote or non-fragment $ref" end
      if value:find("%", 1, true) then return "percent-encoded JSON Pointer fragment" end
      local target = support.resolve(root, value)
      if target == nil then return "$ref that is not a JSON Pointer to a location of the document" end
    elseif SCHEMA_MAPS[key] then
      for _, name in ipairs(sorted_keys(value)) do
        local reason = skip_reason_of_group(value[name], root)
        if reason then return reason end
      end
    elseif SCHEMA_LISTS[key] then
      for _, sub in ipairs(value) do
        local reason = skip_reason_of_group(sub, root)
        if reason then return reason end
      end
    elseif SCHEMA_ONES[key] then
      local reason = skip_reason_of_group(value, root)
      if reason then return reason end
    elseif not DATA[key] then
      return "keyword outside the supported subset: " .. key
    end
  end
  return nil
end

-- Translation of an official schema into a Hecate schema. `skip(reason)` abandons the group.
local function skip(reason) error({ skip = reason }, 0) end

local function whole_number(value) return type(value) == "number" and value == math.floor(value) end

local translate

local LIMITS = {
  string = { minLength = "min_length", maxLength = "max_length" },
  integer = { minimum = "minimum", maximum = "maximum", exclusiveMinimum = "exclusive_minimum",
    exclusiveMaximum = "exclusive_maximum", multipleOf = "multiple_of" },
  number = { minimum = "minimum", maximum = "maximum", exclusiveMinimum = "exclusive_minimum",
    exclusiveMaximum = "exclusive_maximum", multipleOf = "multiple_of" },
  array = { minItems = "min_items", maxItems = "max_items", uniqueItems = "unique_items" },
  object = {},
  boolean = {}, null = {},
}
local ANNOTATIONS = { default = true, description = true, title = true, ["$comment"] = true, ["$schema"] = true, ["$defs"] = true }

local function options_of(node, kind)
  local options = {}
  for _, key in ipairs(sorted_keys(node)) do
    local value = node[key]
    local option = LIMITS[kind][key]
    if option then
      options[option] = value
    elseif key ~= "type" and not ANNOTATIONS[key] and key ~= "properties" and key ~= "required"
      and key ~= "additionalProperties" and key ~= "items" and key ~= "minProperties" and key ~= "maxProperties" then
      skip("untyped or inapplicable keyword: " .. key)
    end
  end
  if kind == "integer" and options.multiple_of and not whole_number(options.multiple_of) then
    skip("multipleOf that is not a whole number (Hecate refuses it)")
  end
  return options
end

local function is_scalar(value) return value == null or type(value) == "string" or type(value) == "number" or type(value) == "boolean" end

function translate(node, root, stack)
  if type(node) == "boolean" then skip("boolean schema") end
  if node["$ref"] then
    for _, key in ipairs(sorted_keys(node)) do
      if key ~= "$ref" and not ANNOTATIONS[key] then skip("$ref with sibling keywords") end
    end
    local target = support.resolve(root, node["$ref"])
    if stack[target] then skip("recursive $ref (Hecate resolves cycles through schema.of)") end
    stack[target] = true
    local result = translate(target, root, stack)
    stack[target] = nil
    return result
  end
  if node.enum or node.const ~= nil then
    for _, key in ipairs(sorted_keys(node)) do
      if key ~= "enum" and key ~= "const" and not ANNOTATIONS[key] then skip("enum or const combined with: " .. key) end
    end
    if node.const ~= nil then
      if not is_scalar(node.const) then skip("const that is an array or an object") end
      return schema.literal(node.const)
    end
    if #node.enum == 0 then skip("empty enum") end
    for _, value in ipairs(node.enum) do
      if not is_scalar(value) then skip("enum with an array or an object") end
    end
    return schema.enumeration(node.enum)
  end
  if node.oneOf then skip("oneOf (a Hecate union is anyOf)") end
  if node.anyOf then
    for _, key in ipairs(sorted_keys(node)) do
      if key ~= "anyOf" and not ANNOTATIONS[key] then skip("anyOf combined with: " .. key) end
    end
    local list = {}
    for i, alternative in ipairs(node.anyOf) do
      list[i] = translate(alternative, root, stack)
      local kind = list[i].kind
      if kind == "null" or kind == "nullable" then
        skip("anyOf with a null alternative (a Hecate union must not contain null, OQ-99)")
      elseif kind == "literal" and list[i].options.value == json.null then
        skip("anyOf with a const null alternative (a Hecate union must not contain null, OQ-100)")
      elseif kind == "enumeration" then
        for _, member in ipairs(list[i]:members()) do
          if member == json.null then
            skip("anyOf with an enum containing null (a Hecate union must not contain null, OQ-100)")
          end
        end
      end
    end
    return schema.union(list)
  end
  local kind = node.type
  if kind == nil then
    for _, key in ipairs(sorted_keys(node)) do
      if not ANNOTATIONS[key] then skip("untyped or inapplicable keyword: " .. key) end
    end
    return schema.any()
  end
  if type(kind) ~= "string" then skip("type array") end
  if kind == "boolean" then options_of(node, kind) return schema.boolean() end
  if kind == "null" then options_of(node, kind) return schema.null() end
  if kind == "string" then return schema.string(options_of(node, kind)) end
  if kind == "integer" then return schema.integer(options_of(node, kind)) end
  if kind == "number" then return schema.number(options_of(node, kind)) end
  if kind == "array" then
    local options = options_of(node, kind)
    local item = node.items ~= nil and translate(node.items, root, stack) or schema.any()
    return schema.array(item, options)
  end
  if kind == "object" then
    options_of(node, kind)
    local additional = node.additionalProperties
    local properties = node.properties or {}
    local required = {}
    for _, name in ipairs(node.required or {}) do required[name] = true end
    if next(properties) == nil and additional ~= nil and type(additional) == "table" and not node.required then
      return schema.map(translate(additional, root, stack), { min_properties = node.minProperties, max_properties = node.maxProperties })
    end
    if node.minProperties or node.maxProperties then skip("minProperties or maxProperties on an object with properties") end
    if type(additional) == "table" then skip("additionalProperties schema next to properties") end
    local declared = {}
    for _, name in ipairs(sorted_keys(properties)) do
      local inner = translate(properties[name], root, stack)
      declared[name] = required[name] and inner or schema.optional(inner)
    end
    for name in pairs(required) do
      if not properties[name] then declared[name] = schema.any() end -- required, any value
    end
    return schema.object(declared, { additional_properties = additional ~= false })
  end
  skip("unknown type " .. tostring(kind))
end

local function is_whole_float(value) return math.type(value) == "float" and value == math.floor(value) end

local function resolve_node(node, root)
  local guard = 0
  while type(node) == "table" and node["$ref"] and guard < 20 do
    node = support.resolve(root, node["$ref"])
    guard = guard + 1
  end
  return node
end

local function allows_integer(type_keyword)
  if type_keyword == "integer" then return true end
  if type(type_keyword) == "table" then
    for _, name in ipairs(type_keyword) do
      if name == "integer" then return true end
    end
  end
  return false
end

--- Whether a whole float sits in `data` at a position where an integer type, a `const` or an `enum` applies (through
--- `$ref`, `anyOf` and `oneOf`, `items`, `properties` and `additionalProperties`), or a whole float written as the `const`
--- or in the `enum` that applies to a number: the only place where the documented gap
--- of OQ-85 point 11 (Lua `integer` refuses `1.0`, JSON Schema section 6.1.1 accepts it) can change a verdict. A whole float
--- elsewhere (under `number`, `any`, a string schema) is no excuse.
local function whole_float_at_integer_position(node, data, root)
  node = resolve_node(node, root)
  if type(node) ~= "table" then return false end
  if is_whole_float(data) then
    if allows_integer(node.type) or node.const ~= nil or node.enum ~= nil then return true end
  end
  if type(data) == "number" then -- the whole float is the constant of the schema (`const: -2.0`, data `-2`)
    if is_whole_float(node.const) then return true end
    for _, constant in ipairs(node.enum or {}) do
      if is_whole_float(constant) then return true end
    end
  end
  for _, keyword in ipairs({ "anyOf", "oneOf" }) do
    for _, alternative in ipairs(node[keyword] or {}) do
      if whole_float_at_integer_position(alternative, data, root) then return true end
    end
  end
  if type(data) == "table" and data ~= null then
    if json.is_array(data) or (#data > 0) then
      if node.items ~= nil then
        for _, member in ipairs(data) do
          if whole_float_at_integer_position(node.items, member, root) then return true end
        end
      end
    else
      for key, member in pairs(data) do
        local property = node.properties and node.properties[key]
        local inner = property
        if inner == nil then inner = node.additionalProperties end
        if inner ~= nil and whole_float_at_integer_position(inner, member, root) then return true end
      end
    end
  end
  return false
end

--- Whether a number of `data` meets, at its position, a schema whose `multipleOf` is not a whole number: the suite expects
--- decimal arithmetic, the checker (and Lua) divide binary floats (`0.0075` is not a multiple of `0.0001` in binary).
local function fractional_divisor_at(node, data, root)
  node = resolve_node(node, root)
  if type(node) ~= "table" then return false end
  if type(data) == "number" and type(node.multipleOf) == "number" and node.multipleOf ~= math.floor(node.multipleOf) then
    return true
  end
  for _, keyword in ipairs({ "anyOf", "oneOf" }) do
    for _, alternative in ipairs(node[keyword] or {}) do
      if fractional_divisor_at(alternative, data, root) then return true end
    end
  end
  if type(data) == "table" and data ~= null then
    if node.items ~= nil then
      for _, member in ipairs(data) do
        if fractional_divisor_at(node.items, member, root) then return true end
      end
    end
    for key, member in pairs(data) do
      local inner = node.properties and node.properties[key]
      if inner == nil then inner = node.additionalProperties end
      if inner ~= nil and fractional_divisor_at(inner, member, root) then return true end
    end
  end
  return false
end

local function read_file(name)
  local file = assert(io.open(dir .. name .. ".json", "rb"))
  local text = file:read("a")
  file:close()
  return json.decode(text)
end

local function increment(counts, key) counts[key] = (counts[key] or 0) + 1 end

local function summary(report)
  local lines = {}
  for key, count in pairs(report.counts) do lines[#lines + 1] = ("  %5d  %s"):format(count, key) end
  table.sort(lines)
  return ("cases run by check and skipped by reason:\n%s"):format(table.concat(lines, "\n"))
end

-- Walks every group; `report.failures` lists the cases that disagree.
local function run_suite()
  local report = { counts = {}, failures = {} }
  for _, name in ipairs(FILES) do
    for _, group in ipairs(read_file(name)) do
      local label = ("%s / %s"):format(name, group.description)
      local root = group.schema
      local reason = skip_reason_of_group(root, root)
      if reason then
        report.counts["skipped (group): " .. reason] = (report.counts["skipped (group): " .. reason] or 0) + #group.tests
      else
        local ok, translated = pcall(translate, root, root, {})
        ---@cast translated any
        local skipped
        if not ok then
          if type(translated) == "table" and translated.skip then skipped = translated.skip else error(translated, 0) end
        end
        local emitted = ok and translated:to_json_schema()
        for _, case in ipairs(group.tests) do
          local case_label = ("%s / %s"):format(label, case.description)
          increment(report.counts, "run: checker on the official schema")
          if support.conforms(root, case.data) == case.valid then
            increment(report.counts, "run: checker agrees")
          elseif fractional_divisor_at(root, case.data, root) then
            increment(report.counts, "gap: fractional multipleOf in binary floats, checker")
          else
            report.failures[#report.failures + 1] = "checker disagrees with the suite: " .. case_label
          end
          if skipped then
            increment(report.counts, "skipped (Hecate schema): " .. skipped)
          else
            local lua_valid = translated:validate(case.data)
            -- The gap has one direction only: Lua says invalid, the suite says valid, at an integer position.
            local gap = whole_float_at_integer_position(root, case.data, root)
            if lua_valid == case.valid then
              increment(report.counts, "run: Schema:validate")
            elseif gap and not lua_valid and case.valid then
              increment(report.counts, "gap: 1.0 (OQ-85 point 11), validate")
            else
              report.failures[#report.failures + 1] = "Schema:validate disagrees with the suite: " .. case_label
            end
            if support.conforms(emitted, case.data) == lua_valid then
              increment(report.counts, "run: emitted schema agrees with Schema:validate")
            elseif gap and not lua_valid then -- the emitted schema (the checker) accepts the whole float Lua refuses
              increment(report.counts, "gap: 1.0 (OQ-85 point 11), emission")
            else
              report.failures[#report.failures + 1] = "emission disagrees with Schema:validate: " .. case_label
            end
          end
        end
      end
    end
  end
  return report
end

-- Pinned counts of the pinned suite revision (tests/external.lua). A new gap fails the test (the upper bounds have no
-- slack), a group that moves into a skip bucket, or out of one, changes a pinned total and fails it too: update the
-- numbers on purpose, after reading why, when the suite revision changes.
local MAX_GAPS = {
  ["gap: 1.0 (OQ-85 point 11), validate"] = 7,
  ["gap: 1.0 (OQ-85 point 11), emission"] = 7,
  ["gap: fractional multipleOf in binary floats, checker"] = 2,
}
local EXPECTED_RUN = {
  ["run: checker on the official schema"] = 460,
  ["run: checker agrees"] = 458,
  ["run: Schema:validate"] = 133,
  ["run: emitted schema agrees with Schema:validate"] = 133,
}
local EXPECTED_SKIPS = {
  ["skipped (Hecate schema): anyOf combined with: type"] = 3,
  ["skipped (Hecate schema): boolean schema"] = 22,
  ["skipped (Hecate schema): const that is an array or an object"] = 19,
  ["skipped (Hecate schema): empty enum"] = 6,
  ["skipped (Hecate schema): enum with an array or an object"] = 20,
  ["skipped (Hecate schema): multipleOf that is not a whole number (Hecate refuses it)"] = 2,
  ["skipped (Hecate schema): anyOf with a null alternative (a Hecate union must not contain null, OQ-99)"] = 2,
  ["skipped (Hecate schema): anyOf with a const null alternative (a Hecate union must not contain null, OQ-100)"] = 0,
  ["skipped (Hecate schema): anyOf with an enum containing null (a Hecate union must not contain null, OQ-100)"] = 0,
  ["skipped (Hecate schema): oneOf (a Hecate union is anyOf)"] = 27,
  ["skipped (Hecate schema): type array"] = 19,
  ["skipped (Hecate schema): untyped or inapplicable keyword: additionalProperties"] = 10,
  ["skipped (Hecate schema): untyped or inapplicable keyword: exclusiveMaximum"] = 4,
  ["skipped (Hecate schema): untyped or inapplicable keyword: exclusiveMinimum"] = 4,
  ["skipped (Hecate schema): untyped or inapplicable keyword: items"] = 9,
  ["skipped (Hecate schema): untyped or inapplicable keyword: maxItems"] = 6,
  ["skipped (Hecate schema): untyped or inapplicable keyword: maxLength"] = 7,
  ["skipped (Hecate schema): untyped or inapplicable keyword: maxProperties"] = 10,
  ["skipped (Hecate schema): untyped or inapplicable keyword: maximum"] = 8,
  ["skipped (Hecate schema): untyped or inapplicable keyword: minItems"] = 6,
  ["skipped (Hecate schema): untyped or inapplicable keyword: minLength"] = 7,
  ["skipped (Hecate schema): untyped or inapplicable keyword: minProperties"] = 10,
  ["skipped (Hecate schema): untyped or inapplicable keyword: minimum"] = 15,
  ["skipped (Hecate schema): untyped or inapplicable keyword: multipleOf"] = 11,
  ["skipped (Hecate schema): untyped or inapplicable keyword: properties"] = 47,
  ["skipped (Hecate schema): untyped or inapplicable keyword: required"] = 9,
  ["skipped (Hecate schema): untyped or inapplicable keyword: uniqueItems"] = 39,
  ["skipped (group): $ref that is not a JSON Pointer to a location of the document"] = 1,
  ["skipped (group): Hecate declares no allOf (an intersection of schemas)"] = 88,
  ["skipped (group): Hecate declares no contains"] = 70,
  ["skipped (group): Hecate declares no dependent keywords"] = 48,
  ["skipped (group): Hecate declares no if/then/else"] = 56,
  ["skipped (group): Hecate declares no not"] = 42,
  ["skipped (group): Hecate declares no patternProperties"] = 67,
  ["skipped (group): Hecate declares no propertyNames"] = 26,
  ["skipped (group): Hecate declares no tuple (prefixItems)"] = 70,
  ["skipped (group): Hecate declares no unevaluated keywords"] = 63,
  ["skipped (group): anchors are not emitted"] = 13,
  ["skipped (group): content keywords are annotations"] = 18,
  ["skipped (group): dynamic references are not emitted"] = 32,
  ["skipped (group): format is an annotation in 2020-12 (section 7.2.1)"] = 133,
  ["skipped (group): identifiers and base URIs are not emitted (one document, local references)"] = 59,
  ["skipped (group): pattern: ECMA-262 expression (the checker has no engine, a Hecate pattern is a Lua pattern, OQ-85)"] = 12,
  ["skipped (group): percent-encoded JSON Pointer fragment"] = 8,
  ["skipped (group): remote or non-fragment $ref"] = 34,
}

function T:test_the_official_cases_agree_with_the_checker_validation_and_emission()
  if not present(self) then return end
  local report = run_suite()
  local shown = {}
  for i = 1, math.min(#report.failures, 15) do shown[i] = report.failures[i] end
  self:assert_equal(0, #report.failures, table.concat(shown, "\n") .. "\n" .. summary(report))
  local counts = report.counts
  -- Guards against a runner that silently runs nothing.
  self:assert_true((counts["run: checker agrees"] or 0) >= 150, summary(report))
  self:assert_true((counts["run: Schema:validate"] or 0) >= 100, summary(report))
  -- The gaps are bounded by what is observed: a new one is a failure.
  for key, maximum in pairs(MAX_GAPS) do
    self:assert_true((counts[key] or 0) <= maximum, ("%s: %d > %d\n%s"):format(key, counts[key] or 0, maximum, summary(report)))
  end
  for key, count in pairs(counts) do
    if key:find("^gap:") and not MAX_GAPS[key] then self:fail("an unlisted gap: " .. key .. "\n" .. summary(report)) end
  end
  -- Emission agreement and the other runs keep at least 90 percent of what is observed.
  for key, observed in pairs(EXPECTED_RUN) do
    self:assert_true((counts[key] or 0) >= observed * 9 // 10, ("%s: %d < 90%% of %d\n%s"):format(key, counts[key] or 0, observed, summary(report)))
  end
  -- The skipped cases, per reason, are pinned exactly.
  for key, expected in pairs(EXPECTED_SKIPS) do
    self:assert_equal(expected, counts[key] or 0, ("%s\n%s"):format(key, summary(report)))
  end
  for key, count in pairs(counts) do
    if key:find("^skipped") and not EXPECTED_SKIPS[key] then
      self:fail(("a new skip reason: %s (%d cases)\n%s"):format(key, count, summary(report)))
    end
  end
  if os.getenv("HECATE_TEST_VERBOSE") then io.stderr:write("# json_schema_suite: " .. summary(report) .. "\n") end
end

return T
