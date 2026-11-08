---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local T = test.Case("SchemaCoerceBuildTest")

local function class_of(name, build, value)
  local C = value and core.value_class(name) or core.class(name)
  function C.schema() return build() end
  core.finalise(C)
  return C
end

local function filter_class(value)
  return class_of(value and "VFilter" or "Filter", function()
    return schema.object({
      status = schema.string(),
      page = schema.default(schema.integer(), 1),
      tags = schema.optional(schema.array(schema.string())),
      limit = schema.optional(schema.integer()),
    })
  end, value)
end

function T:test_build_from_texts_converts_then_builds()
  local Filter = filter_class(false)
  local ok, f = schema.of(Filter):build({ status = "open", page = "2", tags = "a,b" }, { coerce = true })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(f, Filter))
  self:assert_equal("open", f.status)
  self:assert_equal(2, f.page)
  self:assert_equal("integer", math.type(f.page))
  self:assert_equal("b", f.tags[2])
end

function T:test_unconvertible_text_gives_a_coercion_violation_as_coerce()
  local s = schema.of(filter_class(false))
  local ok, violations = s:build({ status = "open", page = "two" }, { coerce = true })
  self:assert_false(ok)
  self:assert_equal("/page", violations[1].path)
  self:assert_equal("coercion", violations[1].code)
  local _, expected = s:coerce({ status = "open", page = "two" })
  self:assert_equal(#expected, #violations)
  self:assert_equal(expected[1].code, violations[1].code)
  self:assert_equal(expected[1].path, violations[1].path)
end

function T:test_default_applies_once_and_is_not_sent()
  local Filter = filter_class(false)
  local ok, f = schema.of(Filter):build({ status = "open" }, { coerce = true })
  self:assert_true(ok)
  self:assert_equal(1, f.page)
  self:assert_false(schema.sent(f, "page"))
  self:assert_true(schema.sent(f, "status"))
  self:assert_false(schema.sent(f, "tags"))
  local _, g = schema.of(Filter):build({ status = "open", page = "1" }, { coerce = true })
  self:assert_true(schema.sent(g, "page"))
end

function T:test_default_of_a_container_is_one_fresh_copy()
  local C = class_of("Cfg", function()
    return schema.object({ opts = schema.default(schema.array(schema.string()), { "x" }) })
  end, false)
  local s = schema.of(C)
  local _, a = s:build({}, { coerce = true })
  local _, b = s:build({}, { coerce = true })
  a.opts[1] = "changed"
  self:assert_equal("x", b.opts[1])
  self:assert_false(a.opts == b.opts)
end

function T:test_patch_keeps_relaxed_required_and_no_default()
  local s = schema.of(filter_class(false))
  local ok, f = s:build({ page = "5" }, { coerce = true, method = "PATCH" })
  self:assert_true(ok)
  self:assert_equal(5, f.page)
  self:assert_nil(f.status)
  local ok2, g = s:build({ limit = "3" }, { coerce = true, method = "PATCH" })
  self:assert_true(ok2)
  self:assert_nil(g.page)
  self:assert_equal(3, g.limit)
  -- the PATCH did not leave a stale flag behind
  local _, c = s:coerce({ status = "open" })
  self:assert_equal(1, c.page)
  local _, h = s:build({ status = "open" }, { coerce = true })
  self:assert_equal(1, h.page)
end

function T:test_post_without_a_required_text_fails()
  local ok, violations = schema.of(filter_class(false)):build({ page = "2" }, { coerce = true })
  self:assert_false(ok)
  self:assert_equal("required", violations[1].code)
end

function T:test_nested_class_bound_parts()
  local Range = class_of("Range", function()
    return schema.object({ lo = schema.integer(), hi = schema.default(schema.integer(), 10) })
  end, false)
  local Query = class_of("Query", function()
    return schema.object({ range = schema.of(Range), ids = schema.array(schema.integer(), { delimiter = "|" }) })
  end, false)
  local ok, q = schema.of(Query):build({ range = { lo = "1" }, ids = "4|5" }, { coerce = true })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(q.range, Range))
  self:assert_equal(1, q.range.lo)
  self:assert_equal(10, q.range.hi)
  self:assert_false(schema.sent(q.range, "hi"))
  self:assert_equal(5, q.ids[2])
end

function T:test_value_class()
  local Filter = filter_class(true)
  local s = schema.of(Filter)
  local ok, f = s:build({ status = "open", page = "2" }, { coerce = true })
  self:assert_true(ok)
  self:assert_true(core.is_instance_of(f, Filter))
  self:assert_equal(2, f.page)
  self:assert_false(pcall(function() f.page = 3 end))
  local _, d = s:build({ status = "open" }, { coerce = true })
  self:assert_equal(1, d.page)
  self:assert_false(schema.sent(d, "page"))
  local _, e = s:build({ status = "open" }, { coerce = true })
  self:assert_true(d == e)
end

function T:test_coerce_option_is_validated_and_absent_changes_nothing()
  local s = schema.of(filter_class(false))
  for _, bad in ipairs({ "yes", 1, {} } --[[@as any[] ]]) do
    local err = self:assert_error(function() return s:build({ status = "a" }, { coerce = bad }) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
  local ok = s:build({ status = "open", page = "2" })
  self:assert_false(ok)
  self:assert_false((s:build({ status = "open", page = "2" }, { coerce = false })))
  local ok2, f = s:build({ status = "open", page = 2 }, { coerce = false })
  self:assert_true(ok2)
  self:assert_equal(2, f.page)
end

return T
