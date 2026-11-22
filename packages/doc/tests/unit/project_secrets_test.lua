-- The configuration reference never prints a secret: the schema is the single source (`writeOnly: true`, JSON Schema
-- 2020-12 9.4, or `format: "password"`), and a default is redacted when the row, or anything reachable from it, is a secret.
-- Every cell is escaped text: a number that is not a finite number, or a table, never reaches the page.
local test = require("harness.test")
local doc = require("hecate.doc")
local project = require("hecate.doc.project")
local T = test.Case("ProjectSecretsTest")

local CANARY = "CANARY-do-not-print"

local function page_of(properties, defs)
  return project.configuration_page({ type = "object", properties = properties, ["$defs"] = defs })
end

local function assert_hidden(self, page, label)
  self:assert_nil(page:find(CANARY, 1, true), (label or "") .. "\n" .. page)
end

local PASSWORD = { type = "string", format = "password" }

function T:test_a_composed_secret_is_redacted()
  local page = page_of({
    any_of = { anyOf = { PASSWORD, { type = "null" } }, default = CANARY },
    one_of = { oneOf = { { type = "string", writeOnly = true }, { type = "integer" } }, default = CANARY },
    all_of = { allOf = { { writeOnly = true }, { type = "string" } }, default = CANARY },
    conditional = { ["if"] = { type = "string" }, ["then"] = { type = "string", writeOnly = true }, default = CANARY },
    otherwise = { ["if"] = { type = "string" }, ["else"] = { writeOnly = true }, default = CANARY },
    mode = { type = "string", default = "dev" },
  })
  assert_hidden(self, page)
  self:assert_not_nil(page:find("[redacted]", 1, true))
  self:assert_not_nil(page:find("`dev`", 1, true), "an ordinary default stays")
end

function T:test_an_array_of_secrets_is_redacted()
  local page = page_of({
    keys = { type = "array", items = { type = "string", writeOnly = true }, default = { CANARY } },
    tuple = { type = "array", prefixItems = { { type = "string" }, PASSWORD }, default = { "a", CANARY } },
    old_tuple = { type = "array", items = { { type = "string" }, PASSWORD }, default = { "a", CANARY } },
  })
  assert_hidden(self, page)
end

function T:test_a_secret_in_the_properties_of_the_items_is_redacted()
  local page = page_of({
    users = { type = "array", items = { type = "object", properties = { name = { type = "string" },
      password = { type = "string", writeOnly = true } } }, default = { { name = "ada", password = CANARY } } },
    nested = { type = "array", items = { type = "array", items = { type = "object", properties = {
      deep = PASSWORD } } }, default = { { { deep = CANARY } } } },
  })
  assert_hidden(self, page)
  self:assert_not_nil(page:find("[redacted]", 1, true))
end

function T:test_a_secret_below_an_object_cut_by_the_depth_limit_is_redacted()
  local leaf = { type = "object", properties = { password = { type = "string", writeOnly = true, default = CANARY } },
    default = { password = CANARY } }
  local node = leaf
  for _ = 1, 8 do
    node = { type = "object", properties = { next = node, label = { type = "string" } }, default = { next = { password = CANARY } } }
  end
  local page = page_of({ root = node })
  assert_hidden(self, page)
end

function T:test_a_secret_below_a_recursion_cut_is_redacted()
  local page = page_of({ tree = { ["$ref"] = "#/$defs/Node" } }, {
    Node = { type = "object", properties = {
      password = { type = "string", writeOnly = true },
      child = { ["$ref"] = "#/$defs/Node", default = { password = CANARY } },
    }, default = { password = CANARY } },
  })
  assert_hidden(self, page)
end

function T:test_a_parent_marked_write_only_hides_what_its_children_carry()
  local page = page_of({
    credentials = { type = "object", writeOnly = true, properties = {
      user = { type = "string", default = CANARY .. "-default" },
      role = { type = "string", enum = { CANARY .. "-enum", "b" } },
      kind = { const = CANARY .. "-const" },
      inner = { type = "object", properties = { token = { type = "string", default = CANARY .. "-inner", pattern = CANARY .. "-pattern" } } },
    } },
  })
  assert_hidden(self, page)
  self:assert_not_nil(page:find("`credentials.user`", 1, true), "the keys are still documented")
  self:assert_not_nil(page:find("`credentials.inner.token`", 1, true))
end

function T:test_a_secret_object_behind_a_reference_is_redacted()
  local page = page_of({
    login = { ["$ref"] = "#/$defs/Login" },
    chain = { ["$ref"] = "#/$defs/Alias" },
    marked = { ["$ref"] = "#/$defs/Marked" },
  }, {
    Login = { type = "object", properties = { user = { type = "string" }, password = PASSWORD }, default = { password = CANARY } },
    Alias = { ["$ref"] = "#/$defs/Login", default = CANARY },
    Marked = { type = "string", writeOnly = true, default = CANARY, enum = { CANARY } },
  })
  assert_hidden(self, page)
end

function T:test_an_unresolvable_reference_fails_closed()
  local page = page_of({ remote = { ["$ref"] = "https://example.test/schema.json", default = CANARY } })
  assert_hidden(self, page)
end

function T:test_secrets_in_additional_and_pattern_properties_are_redacted()
  local page = page_of({
    map = { type = "object", additionalProperties = { type = "string", writeOnly = true }, default = { a = CANARY } },
    by_name = { type = "object", patternProperties = { ["^x"] = PASSWORD }, default = { x1 = CANARY } },
    open = { type = "object", unevaluatedProperties = PASSWORD, default = { x = CANARY } },
    dependent = { type = "object", dependentSchemas = { a = { properties = { b = PASSWORD } } }, default = { b = CANARY } },
  })
  assert_hidden(self, page)
end

function T:test_the_enumeration_and_the_constant_of_a_secret_are_not_printed()
  local page = page_of({ key = { type = "string", writeOnly = true, enum = { CANARY, "b" }, const = CANARY, pattern = CANARY } })
  assert_hidden(self, page)
end

function T:test_a_search_over_a_huge_schema_stays_bounded_and_fails_closed()
  local wide = {}
  for index = 1, 450 do wide["p" .. index] = { type = "string" } end
  local row = { type = "object", properties = wide, default = { p1 = CANARY } }
  local started = os.clock()
  local page = page_of({ big = row })
  self:assert_true(os.clock() - started < 5, "the work is bounded")
  self:assert_equal("string", type(page))
end

-- Markdown injection ---------------------------------------------------------------------------------------------

local ATTACK = "x |\n\n[click](https://evil.example) # heading"

local function assert_table_intact(self, page)
  self:assert_nil(page:find("[click](https://evil.example)", 1, true), page)
  self:assert_nil(page:find("evil.example", 1, true), page)
  local in_table = false
  for line in (page .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("^| Key |", 1) then in_table = true
    elseif in_table and line ~= "" then self:assert_equal("|", line:sub(1, 1), line)
    elseif in_table and line == "" then in_table = false end
  end
end

function T:test_a_hostile_number_constraint_never_reaches_the_page()
  for _, key in ipairs({ "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength",
    "minItems", "maxItems" }) do
    local page = page_of({ n = { type = "integer", [key] = ATTACK }, after = { type = "string" } })
    assert_table_intact(self, page)
    self:assert_not_nil(page:find("`after`", 1, true), key)
  end
end

function T:test_a_table_or_a_function_value_never_prints_an_address()
  local values = { {}, function() end, coroutine.create(function() end), io.stdout, true }
  for _, value in ipairs(values) do
    local page = page_of({ n = { type = "integer", minimum = value, maximum = value, minLength = value, multipleOf = value,
      description = value, pattern = value, format = value, default = value, enum = { value }, const = value } })
    self:assert_nil(page:find("0x", 1, true), tostring(value) .. "\n" .. page)
    self:assert_nil(page:find("table: ", 1, true))
    self:assert_nil(page:find("function: ", 1, true))
    self:assert_nil(page:find("thread: ", 1, true))
    self:assert_nil(page:find("file (", 1, true))
  end
  local with_description = project.configuration_page({ type = "object", description = {}, properties = {} })
  self:assert_nil(with_description:find("0x", 1, true))
  self:assert_equal(page_of({ n = { minimum = {} } }), page_of({ n = { minimum = {} } }), "deterministic")
end

function T:test_only_finite_numbers_are_written()
  local page = page_of({
    a = { type = "integer", minimum = 1, maximum = 65535 }, b = { type = "number", minimum = 0.5 },
    c = { type = "number", maximum = 1 / 0, minimum = -1 / 0 }, d = { type = "number", minimum = 0 / 0 },
    e = { type = "string", minLength = 2, maxLength = 9 }, f = { type = "number", multipleOf = 5 },
  })
  self:assert_not_nil(page:find("1 to 65535", 1, true), page)
  self:assert_not_nil(page:find("at least 0.5", 1, true), page)
  self:assert_not_nil(page:find("length at least 2; length at most 9", 1, true), page)
  self:assert_not_nil(page:find("multiple of 5", 1, true), page)
  self:assert_nil(page:find("inf", 1, true), page)
  self:assert_nil(page:find("nan", 1, true), page)
end

return T
