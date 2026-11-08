---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible
-- Every violation code of the "Violation codes" table of `docs/architecture/schemas-and-contracts.md` can be produced, with
-- the path, the message and the context fields the table documents (review finding q1): the table of the document is
-- parsed here, compared with the codes of the Lua table below and with the `hecate.schema.ViolationCode` alias, so that
-- neither the document, the annotation nor the tests can drift from the others.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaViolationCodesTest")

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local protected = dofile(here .. "/../support/protected.lua")
local SPEC = here .. "/../../../../docs/architecture/schemas-and-contracts.md"
local ALIAS = here .. "/../../src/hecate/schema/violation.lua"

local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

--- The rows of the table: `code` to the list of backticked context fields of its row and the fields after "and" (optional).
local function documented()
  local codes, order = {}, {}
  local inside = false
  for line in read(SPEC):gmatch("[^\r\n]+") do
    if line:find("^| Code | Context fields | Emitted by |") then
      inside = true
    elseif inside and line:find("^|%-%-%-") then
      -- the separator row
    elseif inside and line:find("^|") then
      local first, second = line:match("^|%s*(.-)%s*|%s*(.-)%s*|")
      local fields, optional, after_and = {}, {}, false
      if second ~= "none" then
        for part in second:gmatch("[^,]+") do
          if part:find("and") then after_and = true end
          local name = part:match("`([%w_]+)`")
          if name then
            if after_and then optional[name] = true else fields[#fields + 1] = name end
          end
        end
      end
      for code in first:gmatch("`([%w_]+)`") do
        codes[code] = { fields = fields, optional = optional, none = second == "none" }
        order[#order + 1] = code
      end
    elseif inside then
      break
    end
  end
  return codes, order
end

local function alias_codes()
  local list = {}
  local text = read(ALIAS)
  local block = text:match("---@alias hecate%.schema%.ViolationCode\n(.-)\n\n") or ""
  for code in block:gmatch('%-%-%-| "([%w_]+)"') do list[#list + 1] = code end
  return list
end

local function sorted(list)
  local copy = { table.unpack(list) }
  table.sort(copy)
  return copy
end

--- A chain of `depth` nested objects of a class that holds an optional `next` of itself.
local function chain_schema()
  local Chain = core.class("CodesChain", nil, { implements = { schema.Representable } })
  function Chain.schema() return schema.object({ next = schema.optional(schema.of(Chain)) }) end
  core.finalise(Chain)
  return schema.of(Chain)
end

local function chain_value(depth)
  local root = {}
  local node = root
  for _ = 1, depth do
    local child = {}
    node.next = child
    node = child
  end
  return root
end

local SENTINEL = "SECRET-VALUE-4711"
local ONE = schema.object({ v = schema.string({ min_length = 100 }) })

-- code to { run = function() return violation end, path = expected path }. `run` returns the violation of that code.
local function first(code, violations)
  for _, violation in ipairs(violations) do
    if violation.code == code then return violation end
  end
  error(("no %s violation among %d violations: %s"):format(code, #violations, tostring(violations[1])), 0)
end

local function validated(s, value)
  local ok, violations = s:validate(value)
  assert(not ok, "expected a violation")
  return violations
end

local PRODUCERS = {
  type = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.integer() }), { v = SENTINEL })
  end },
  required = { path = "/a", run = function() return validated(schema.object({ a = schema.string() }), {}) end },
  additional_properties = { path = "/extra", run = function() return validated(schema.object({}), { extra = 1 }) end },
  minimum = { path = "/v", secret = "-987654", run = function()
    return validated(schema.object({ v = schema.integer({ minimum = 1 }) }), { v = -987654 })
  end },
  maximum = { path = "/v", secret = "987654", run = function()
    return validated(schema.object({ v = schema.number({ maximum = 1 }) }), { v = 987654 })
  end },
  exclusive_minimum = { path = "/v", run = function()
    return validated(schema.object({ v = schema.integer({ exclusive_minimum = 1 }) }), { v = 1 })
  end },
  exclusive_maximum = { path = "/v", run = function()
    return validated(schema.object({ v = schema.integer({ exclusive_maximum = 1 }) }), { v = 1 })
  end },
  multiple_of = { path = "/v", run = function()
    return validated(schema.object({ v = schema.integer({ multiple_of = 2 }) }), { v = 3 })
  end },
  min_length = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.string({ min_length = 100 }) }), { v = SENTINEL })
  end },
  max_length = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.string({ max_length = 3 }) }), { v = SENTINEL })
  end },
  invalid_utf8 = { path = "/v", run = function() return validated(ONE, { v = "\xff\xfe" }) end },
  pattern = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.string({ pattern = "^%d+$" }) }), { v = SENTINEL })
  end },
  format = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.string({ format = "uuid" }) }), { v = SENTINEL })
  end },
  literal = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.literal("a") }), { v = SENTINEL })
  end },
  enum = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.enumeration({ "a", "b" }) }), { v = SENTINEL })
  end },
  min_items = { path = "/v", run = function()
    return validated(schema.object({ v = schema.array(schema.string(), { min_items = 2 }) }), { v = { "a" } })
  end },
  max_items = { path = "/v", run = function()
    return validated(schema.object({ v = schema.array(schema.string(), { max_items = 1 }) }), { v = { "a", "b" } })
  end },
  unique_items = { path = "/v/1", run = function()
    return validated(schema.object({ v = schema.array(schema.string(), { unique_items = true }) }), { v = { "a", "a" } })
  end },
  min_properties = { path = "/v", run = function()
    return validated(schema.object({ v = schema.map(schema.string(), { min_properties = 2 }) }), { v = { a = "x" } })
  end },
  max_properties = { path = "/v", run = function()
    return validated(schema.object({ v = schema.map(schema.string(), { max_properties = 1 }) }), { v = { a = "x", b = "y" } })
  end },
  union = { path = "/v", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.union({ schema.integer(), schema.boolean() }) }), { v = SENTINEL })
  end },
  tagged_union = { path = "/v/kind", secret = SENTINEL, run = function()
    return validated(schema.object({ v = schema.tagged_union("kind", { a = schema.object({}) }) }), { v = { kind = SENTINEL } })
  end },
  coercion = { path = "/v", secret = SENTINEL, run = function()
    local ok, violations = schema.object({ v = schema.integer() }):coerce({ v = SENTINEL })
    assert(not ok)
    return violations
  end },
  depth_limit = { path = ("/next"):rep(1000), run = function() return validated(chain_schema(), chain_value(1100)) end },
  complexity_limit = { path = "/", prefix = true, run = function()
    local violations
    protected.with_fields(schema._limits, { max_steps = 3 }, function()
      violations = validated(schema.array(schema.object({})), { {}, {}, {}, {}, {} })
    end)
    return violations
  end },
  -- the path is that of the 101st violation, and undeclared properties are visited in the order of `next`: only "/k" is stable
  too_many_violations = { path = "/k", prefix = true, run = function()
    local value = {}
    for i = 1, 101 do value["k" .. i] = i end
    return validated(schema.object({}), value)
  end },
}

function T:test_the_document_the_alias_and_the_tests_list_the_same_codes()
  local codes, order = documented()
  self:assert_true(#order >= 26, "parsed only " .. #order .. " codes from the document")
  local from_tests = {}
  for code in pairs(PRODUCERS) do from_tests[#from_tests + 1] = code end
  self:assert_equal(table.concat(sorted(order), " "), table.concat(sorted(from_tests), " "),
    "the codes of the document and the codes the tests can produce differ")
  self:assert_equal(table.concat(sorted(order), " "), table.concat(sorted(alias_codes()), " "),
    "the codes of the document and of hecate.schema.ViolationCode differ")
end

function T:test_the_document_names_the_context_fields_it_documents()
  local codes = documented()
  self:assert_equal(2, #codes.type.fields) -- expected, received
  self:assert_true(codes.invalid_utf8.none)
  self:assert_true(codes.pattern.optional.reason and codes.pattern.optional.max_bytes)
  self:assert_equal("alternatives", codes.union.fields[1])
end

function T:test_every_code_is_produced_with_its_path_message_and_documented_context()
  local codes = documented()
  local names = {}
  for code in pairs(PRODUCERS) do names[#names + 1] = code end
  table.sort(names)
  for _, code in ipairs(names) do
    local producer = PRODUCERS[code]
    local violation = first(code, producer.run())
    local label = code .. ": " .. tostring(violation)
    self:assert_equal(code, violation.code, label)
    if producer.prefix then
      self:assert_equal(producer.path, violation.path:sub(1, #producer.path), label)
    else
      self:assert_equal(producer.path, violation.path, label)
    end
    self:assert_equal("string", type(violation.message), label)
    self:assert_true(#violation.message > 0, label)
    if producer.secret then
      self:assert_nil(violation.message:find(producer.secret, 1, true), label .. ": the message echoes the value")
    end
    local documented_row = codes[code]
    self:assert_equal("table", type(violation.context), label)
    -- every documented field is present (for a shared row, the field named like the code), and nothing else
    local allowed = {}
    for _, name in ipairs(documented_row.fields) do allowed[name] = true end
    for name in pairs(documented_row.optional) do allowed[name] = true end
    local shared = false
    for _, name in ipairs(documented_row.fields) do if name == code then shared = true end end
    if documented_row.none then
      self:assert_nil(next(violation.context), label .. ": expected no context")
    elseif shared then
      self:assert_not_nil(violation.context[code], label .. ": missing context." .. code)
    else
      for _, name in ipairs(documented_row.fields) do
        self:assert_not_nil(violation.context[name], label .. ": missing context." .. name)
      end
    end
    for name in pairs(violation.context) do
      self:assert_true(allowed[name] == true, label .. ": undocumented context field " .. tostring(name))
    end
  end
end

function T:test_the_optional_context_fields_of_pattern_and_format_appear_with_their_reason()
  protected.with_fields(schema._limits, { max_pattern_bytes = 4 }, function()
    local s = schema.object({ p = schema.string({ pattern = "^a*$" }), f = schema.string({ format = "uuid" }) })
    local violations = validated(s, { p = ("a"):rep(5), f = ("a"):rep(5) })
    local pattern, format = first("pattern", violations), first("format", violations)
    self:assert_equal("too_long_for_pattern", pattern.context.reason)
    self:assert_equal(4, pattern.context.max_bytes)
    self:assert_equal("^a*$", pattern.context.pattern)
    self:assert_equal("too_long_for_pattern", format.context.reason)
    self:assert_equal("uuid", format.context.format)
  end)
  local complex = validated(schema.object({ p = schema.string({ pattern = ("a?"):rep(300) }) }), { p = ("a"):rep(300) })
  self:assert_equal("malformed_pattern", first("pattern", complex).context.reason)
end

function T:test_the_tagged_union_and_union_contexts_carry_what_the_document_says()
  local violation = first("tagged_union", PRODUCERS.tagged_union.run())
  self:assert_equal("kind", violation.context.tag)
  self:assert_equal("a", violation.context.values[1])
  local union = first("union", PRODUCERS.union.run())
  self:assert_equal(2, #union.context.alternatives)
  local enum = first("enum", PRODUCERS.enum.run())
  self:assert_equal(2, #enum.context.values)
  self:assert_equal(1, first("unique_items", PRODUCERS.unique_items.run()).context.index)
end

function T:test_the_violation_is_a_value_that_encodes()
  for code, producer in pairs(PRODUCERS) do
    local violation = first(code, producer.run())
    local ok = pcall(json.encode, { path = violation.path, code = violation.code, message = violation.message })
    self:assert_true(ok, code)
  end
end

return T
