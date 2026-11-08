---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible, assign-type-mismatch, missing-parameter, redundant-parameter
-- Bad options and bad arguments of every constructor (review finding q1): each documented option refuses a wrong-typed
-- value with an `ArgumentError` whose `context.option` names it, an unknown option is refused the same way and lists the
-- accepted ones, and every constructor refuses a wrong argument with an `ArgumentError`. The accepted names of each
-- constructor are read from its own refusal (`context.accepted`) and compared with the table below, so that a new option
-- cannot be added without a row here.
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("SchemaOptionsTest")

local ONE = schema.integer()

-- constructor, how to call it with an options table, and the Lua type each documented option expects.
local WITH_OPTIONS = {
  { name = "string", call = function(options) return schema.string(options) end,
    spec = { min_length = "integer", max_length = "integer", pattern = "string", format = "string", logger = "table" } },
  { name = "integer", call = function(options) return schema.integer(options) end,
    spec = { minimum = "number", maximum = "number", exclusive_minimum = "number", exclusive_maximum = "number",
      multiple_of = "number" } },
  { name = "number", call = function(options) return schema.number(options) end,
    spec = { minimum = "number", maximum = "number", exclusive_minimum = "number", exclusive_maximum = "number",
      multiple_of = "number" } },
  { name = "array", call = function(options) return schema.array(ONE, options) end,
    spec = { min_items = "integer", max_items = "integer", delimiter = "string", unique_items = "boolean" } },
  { name = "object", call = function(options) return schema.object({}, options) end,
    spec = { additional_properties = "boolean" } },
  { name = "map", call = function(options) return schema.map(ONE, options) end,
    spec = { min_properties = "integer", max_properties = "integer" } },
  { name = "build", call = function(options) return ONE:build(1, options) end,
    spec = { method = "string", coerce = "boolean" } },
}

local WRONG = {
  integer = { "1", 1.5, 2.0, true, {}, function() end },
  number = { "1", true, {}, 0 / 0, math.huge, -math.huge },
  string = { 1, true, {}, function() end },
  boolean = { 1, "true", {} },
  table = { "x", 1, true },
}

local function raised(fn)
  local ok, err = pcall(fn)
  if ok then return nil end
  return err
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function assert_argument_error(self, err, label)
  self:assert_not_nil(err, label .. ": no error")
  self:assert_true(core.is_instance_of(err, core.ArgumentError), label .. ": " .. tostring(err))
end

function T:test_an_unknown_option_is_refused_and_lists_the_accepted_ones()
  for _, constructor in ipairs(WITH_OPTIONS) do
    local err = raised(function() constructor.call({ bogus_option = true }) end)
    assert_argument_error(self, err, constructor.name)
    self:assert_equal("bogus_option", err.context.option, constructor.name)
    self:assert_equal(table.concat(sorted_keys(constructor.spec), ","), table.concat(err.context.accepted, ","),
      constructor.name .. ": the accepted options differ from the documented table of this test")
    self:assert_true(err.message:find("bogus_option", 1, true) ~= nil, constructor.name)
    self:assert_true(err.message:find(constructor.name, 1, true) ~= nil, constructor.name)
  end
end

function T:test_every_option_refuses_a_wrong_typed_value_and_names_itself()
  local checked = 0
  for _, constructor in ipairs(WITH_OPTIONS) do
    for _, option in ipairs(sorted_keys(constructor.spec)) do
      for index, value in ipairs(WRONG[constructor.spec[option]]) do
        local err = raised(function() constructor.call({ [option] = value }) end)
        local label = ("%s option %s wrong value #%d (%s)"):format(constructor.name, option, index, type(value))
        assert_argument_error(self, err, label)
        self:assert_equal(option, err.context.option, label)
        self:assert_true(err.message:find(option, 1, true) ~= nil, label)
        checked = checked + 1
      end
    end
  end
  self:assert_true(checked >= 80, "only " .. checked .. " wrong values tried")
end

function T:test_options_that_are_not_a_table_are_refused()
  for _, constructor in ipairs(WITH_OPTIONS) do
    for _, options in ipairs({ "x", 1, true }) do
      assert_argument_error(self, raised(function() constructor.call(options) end), constructor.name .. " " .. type(options))
    end
  end
end

function T:test_a_failed_declaration_leaves_no_schema_and_a_later_one_still_works()
  local before = schema.string({ min_length = 1 })
  self:assert_error(function() schema.string({ min_length = "x" }) end)
  self:assert_true((before:validate("a")))
  self:assert_true((schema.string({ min_length = 1 }):validate("a")))
end

-- Values that are options of the right type but refused by a rule of the constructor, with the option they name.
function T:test_refused_values_of_the_right_type_name_their_option()
  local cases = {
    { "string", { min_length = 3, max_length = 1 }, "min_length" },
    { "string", { format = "nope" }, "format" },
    { "string", { pattern = "%" }, "pattern" },
    { "integer", { multiple_of = 0 }, "multiple_of" },
    { "integer", { multiple_of = 1.5 }, "multiple_of" },
    { "number", { multiple_of = 0.1 }, "multiple_of" },
    { "integer", { minimum = 5, maximum = 1 }, "minimum" },
    { "array", { delimiter = "" }, "delimiter" },
    { "array", { min_items = 3, max_items = 1 }, "min_items" },
    { "map", { min_properties = 3, max_properties = 1 }, "min_properties" },
    { "build", { method = "TRACE" }, "method" },
  }
  for _, case in ipairs(cases) do
    local constructor
    for _, candidate in ipairs(WITH_OPTIONS) do
      if candidate.name == case[1] then constructor = candidate end
    end
    local err = raised(function() constructor.call(case[2]) end)
    assert_argument_error(self, err, case[1] .. " " .. case[3])
    self:assert_equal(case[3], err.context.option, case[1])
  end
end

-- Constructors without options: a wrong argument is an ArgumentError ----------------------------------------------------

local WRONG_ARGUMENTS = {
  { "literal", function() return schema.literal({}) end },
  { "literal", function() return schema.literal() end },
  { "literal", function() return schema.literal(function() end) end },
  { "enumeration", function() return schema.enumeration("x") end },
  { "enumeration", function() return schema.enumeration({}) end },
  { "enumeration", function() return schema.enumeration({ {} }) end },
  { "optional", function() return schema.optional(1) end },
  { "optional", function() return schema.optional(schema.optional(ONE)) end },
  { "nullable", function() return schema.nullable("x") end },
  { "union", function() return schema.union("x") end },
  { "union", function() return schema.union({}) end },
  { "union", function() return schema.union({ 1 }) end },
  { "tagged_union", function() return schema.tagged_union(1, {}) end },
  { "tagged_union", function() return schema.tagged_union("k", "x") end },
  { "tagged_union", function() return schema.tagged_union("k", {}) end },
  { "tagged_union", function() return schema.tagged_union("k", { a = 1 }) end },
  { "tagged_union", function() return schema.tagged_union("k", { a = ONE }) end },
  { "default", function() return schema.default(1, 2) end },
  { "default", function() return schema.default(ONE, "x") end },
  { "named", function() return schema.named(1, ONE) end },
  { "named", function() return schema.named("", ONE) end },
  { "named", function() return schema.named("a b", ONE) end },
  { "named", function() return schema.named("a", 1) end },
  { "of", function() return schema.of(1) end },
  { "of", function() return schema.of(nil) end },
  { "array", function() return schema.array(1) end },
  { "map", function() return schema.map("x") end },
  { "object", function() return schema.object("x") end },
  { "object", function() return schema.object({ a = 1 }) end },
  { "object", function() return schema.object({ [1] = ONE }) end },
  { "string", function() return schema.string("x") end },
  { "integer", function() return schema.integer("x") end },
  { "number", function() return schema.number(1) end },
}

function T:test_every_constructor_refuses_a_wrong_argument_with_an_argument_error()
  local seen = {}
  for index, case in ipairs(WRONG_ARGUMENTS) do
    local err = raised(case[2])
    local label = ("%s, case #%d"):format(case[1], index)
    assert_argument_error(self, err, label)
    self:assert_true(err.message:find(case[1], 1, true) ~= nil, label .. ": the message does not name the constructor: " .. err.message)
    seen[case[1]] = true
  end
  -- Every constructor that takes an argument has a row here (boolean, any and null take none).
  for _, name in ipairs({ "string", "integer", "number", "literal", "enumeration", "optional", "nullable", "union",
    "tagged_union", "default", "named", "of", "array", "map", "object" }) do
    self:assert_true(seen[name], "no wrong argument tried for " .. name)
  end
end

function T:test_constructors_without_options_ignore_a_stray_argument_without_changing_the_schema()
  -- boolean, any and null have no option: a stray argument is not an error, and the schema is the plain one.
  self:assert_true((schema.boolean({ x = 1 }):validate(true)))
  self:assert_false((schema.boolean({ x = 1 }):validate("true")))
  self:assert_true((schema.any({ x = 1 }):validate({})))
  self:assert_true((schema.null({ x = 1 }):validate(require("hecate.json").null)))
end

function T:test_a_module_or_class_that_does_not_resolve_is_refused_when_used_not_when_named()
  -- `of` is lazy: naming a missing module is no error until the schema is used (cycles need it).
  local lazy = schema.of("hecate.no.such.module")
  local err = raised(function() return lazy:validate({}) end)
  self:assert_not_nil(err)
  -- A table that is not a class is refused at declaration.
  assert_argument_error(self, raised(function() return schema.of({}) end), "of({})")
end

return T
