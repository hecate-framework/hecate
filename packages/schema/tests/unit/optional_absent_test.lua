---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaOptionalAbsentTest")

-- schemas-and-contracts.md: `optional` allows an absent value (nil), which is not JSON null.
local function body() return schema.optional(schema.object({ name = schema.string() })) end

function T:test_validate_accepts_an_absent_top_level_value()
  local ok = body():validate(nil)
  self:assert_true(ok)
end

function T:test_coerce_accepts_an_absent_top_level_value()
  local ok, converted = body():coerce(nil)
  self:assert_true(ok)
  self:assert_nil(converted)
end

function T:test_build_accepts_an_absent_top_level_value_whatever_the_options()
  for _, options in ipairs({ false, { coerce = true }, { method = "PATCH" }, { method = "PUT" },
    { coerce = true, method = "PATCH" } }) do
    local ok, built = body():build(nil, options or nil)
    self:assert_true(ok)
    self:assert_nil(built)
  end
end

function T:test_a_present_value_is_still_validated()
  local ok, violations = body():build({ name = 1 })
  self:assert_false(ok)
  self:assert_equal("/name", violations[1].path)
  self:assert_true((body():build({ name = "x" })))
end

function T:test_null_is_not_absent()
  self:assert_false((body():build(json.null)))
  self:assert_false((body():validate(json.null)))
  self:assert_true((schema.optional(schema.nullable(schema.string())):build(json.null)))
end

function T:test_a_required_schema_still_refuses_an_absent_value()
  self:assert_false((schema.object({}):build(nil)))
  self:assert_false((schema.object({}):validate(nil)))
end

return T
