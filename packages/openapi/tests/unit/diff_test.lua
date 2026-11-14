---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests index tables they just asserted exist and pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local openapi = require("hecate.openapi")
local T = test.Case("OpenApiDiffTest")

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

--- A document with one operation `GET /items` built from `operation`, and the given component schemas.
local function document(operation, schemas)
  return { openapi = "3.1.0", info = { title = "T", version = "1" },
    paths = { ["/items"] = { get = operation } }, components = { schemas = schemas or {} } }
end

local function op(fields)
  local operation = { responses = { ["200"] = { description = "OK", content = { ["application/json"] = {
    schema = { type = "object", properties = { id = { type = "integer" } }, required = { "id" } } } } } } }
  for key, value in pairs(fields or {}) do operation[key] = value end
  return operation
end

--- The changes between `base` and a copy of it modified by `mutate`.
local function changes_of(case, mutate, base)
  local old = base or document(op())
  local new = copy(old)
  mutate(new)
  return openapi.diff(old, new), old
end

local function only(case, changes, kind, breaking)
  local found = {}
  for _, change in ipairs(changes) do
    if change.kind == kind then found[#found + 1] = change end
  end
  case:assert_equal(1, #found, "expected exactly one " .. kind)
  case:assert_equal(breaking, found[1].breaking, kind)
  case:assert_equal("string", type(found[1].path))
  case:assert_equal("string", type(found[1].message))
  return found[1]
end

local function get(new) return new.paths["/items"].get end
local function response_schema(new) return get(new).responses["200"].content["application/json"].schema end

local function input_document(input_schema, required)
  return document(op { requestBody = { required = required ~= false, content = { ["application/json"] = { schema = input_schema } } } })
end

local function input_changes(old_schema, new_schema)
  return openapi.diff(input_document(old_schema), input_document(new_schema))
end

function T:test_identical_documents_have_no_changes()
  local doc = document(op())
  self:assert_equal(0, #openapi.diff(doc, copy(doc)))
end

function T:test_invalid_arguments_raise_argument_error()
  local err = self:assert_error(function() openapi.diff(nil, {}) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  err = self:assert_error(function() openapi.diff({}, 3) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
end

function T:test_removed_path_is_breaking()
  local changes = changes_of(self, function(new) new.paths["/items"] = nil end)
  local change = only(self, changes, "path_removed", true)
  self:assert_equal("/items", change.path)
end

function T:test_added_path_is_not_breaking()
  local changes = changes_of(self, function(new) new.paths["/other"] = { get = op() } end)
  only(self, changes, "path_added", false)
end

function T:test_removed_operation_is_breaking()
  local base = document(op())
  base.paths["/items"].post = op()
  local changes = changes_of(self, function(new) new.paths["/items"].post = nil end, base)
  local change = only(self, changes, "operation_removed", true)
  self:assert_equal("POST /items", change.path)
end

function T:test_added_operation_is_not_breaking()
  local changes = changes_of(self, function(new) new.paths["/items"].delete = op() end)
  only(self, changes, "operation_added", false)
end

function T:test_removed_parameter_is_breaking()
  local base = document(op { parameters = { { name = "q", ["in"] = "query", required = false, schema = { type = "string" } } } })
  local changes = changes_of(self, function(new) get(new).parameters = nil end, base)
  only(self, changes, "parameter_removed", true)
end

function T:test_added_required_parameter_is_breaking()
  local changes = changes_of(self, function(new)
    get(new).parameters = { { name = "q", ["in"] = "query", required = true, schema = { type = "string" } } }
  end)
  only(self, changes, "parameter_added_required", true)
end

function T:test_added_optional_parameter_is_not_breaking()
  local changes = changes_of(self, function(new)
    get(new).parameters = { { name = "q", ["in"] = "query", required = false, schema = { type = "string" } } }
  end)
  only(self, changes, "parameter_added", false)
end

function T:test_parameter_becoming_required_is_breaking_and_the_reverse_is_not()
  local optional = document(op { parameters = { { name = "q", ["in"] = "query", required = false, schema = { type = "string" } } } })
  local required = copy(optional)
  get(required).parameters[1].required = true
  only(self, openapi.diff(optional, required), "parameter_required", true)
  only(self, openapi.diff(required, optional), "parameter_optional", false)
end

function T:test_parameter_schema_is_compared_as_input()
  local base = document(op { parameters = { { name = "n", ["in"] = "query", required = true, schema = { type = "integer" } } } })
  local changes = changes_of(self, function(new) get(new).parameters[1].schema = { type = "string" } end, base)
  local change = only(self, changes, "type_narrowed", true)
  self:assert_true(change.path:find("n", 1, true) ~= nil)
end

function T:test_request_body_made_required_is_breaking()
  local optional = input_document({ type = "object" }, false)
  local required = input_document({ type = "object" }, true)
  only(self, openapi.diff(optional, required), "request_body_required", true)
  only(self, openapi.diff(required, optional), "request_body_optional", false)
end

function T:test_added_request_body_depends_on_required()
  local none = document(op())
  only(self, openapi.diff(none, input_document({ type = "object" }, true)), "request_body_added_required", true)
  only(self, openapi.diff(none, input_document({ type = "object" }, false)), "request_body_added", false)
end

function T:test_removed_request_media_type_is_breaking()
  local old = document(op { requestBody = { required = true, content = {
    ["application/json"] = { schema = { type = "object" } }, ["text/plain"] = { schema = { type = "string" } } } } })
  local new = copy(old)
  get(new).requestBody.content["text/plain"] = nil
  only(self, openapi.diff(old, new), "media_type_removed", true)
  only(self, openapi.diff(new, old), "media_type_added", false)
end

function T:test_input_type_change_is_breaking()
  only(self, input_changes({ type = "string" }, { type = "integer" }), "type_narrowed", true)
  only(self, input_changes({ type = "integer" }, { type = "number" }), "type_widened", false)
  only(self, input_changes({ type = "number" }, { type = "integer" }), "type_narrowed", true)
  only(self, input_changes({ type = "string" }, { type = { "string", "null" } }), "type_widened", false)
end

function T:test_input_new_required_property_is_breaking()
  local old = { type = "object", properties = { a = { type = "string" } }, required = { "a" } }
  local new = copy(old)
  new.properties.b = { type = "string" }
  new.required = { "a", "b" }
  local changes = input_changes(old, new)
  local change = only(self, changes, "required_added", true)
  self:assert_true(change.message:find("b", 1, true) ~= nil)
  only(self, changes, "property_added", false)
  only(self, input_changes(new, old), "required_removed", false)
end

function T:test_input_added_optional_property_is_not_breaking()
  local old = { type = "object", properties = { a = { type = "string" } } }
  local new = copy(old)
  new.properties.b = { type = "string" }
  local changes = input_changes(old, new)
  self:assert_equal(1, #changes)
  only(self, changes, "property_added", false)
end

function T:test_input_enum_values_removed_is_breaking()
  local changes = input_changes({ enum = { "a", "b" } }, { enum = { "a" } })
  local change = only(self, changes, "enum_values_removed", true)
  self:assert_nil(change.message:find('"a"', 1, true), "the message holds no enum value")
  only(self, input_changes({ enum = { "a" } }, { enum = { "a", "b" } }), "enum_values_added", false)
end

function T:test_input_stricter_bounds_are_breaking()
  only(self, input_changes({ type = "integer", minimum = 1 }, { type = "integer", minimum = 5 }), "bound_narrowed", true)
  only(self, input_changes({ type = "integer", maximum = 9 }, { type = "integer", maximum = 5 }), "bound_narrowed", true)
  only(self, input_changes({ type = "string" }, { type = "string", maxLength = 8 }), "bound_narrowed", true)
  only(self, input_changes({ type = "array" }, { type = "array", minItems = 1 }), "bound_narrowed", true)
  only(self, input_changes({ type = "integer", minimum = 5 }, { type = "integer", minimum = 1 }), "bound_widened", false)
  only(self, input_changes({ type = "string", maxLength = 8 }, { type = "string" }), "bound_widened", false)
end

function T:test_input_pattern_is_a_constraint()
  only(self, input_changes({ type = "string" }, { type = "string", pattern = "^a" }), "constraint_narrowed", true)
  only(self, input_changes({ type = "string", pattern = "^a" }, { type = "string" }), "constraint_widened", false)
end

function T:test_input_unanalysed_keyword_change_is_breaking()
  only(self, input_changes({ oneOf = { { type = "string" } } }, { oneOf = { { type = "integer" } } }), "schema_changed", true)
end

function T:test_input_nested_property_and_items_are_compared()
  local old = { type = "object", properties = { tags = { type = "array", items = { type = "string" } } } }
  local new = copy(old)
  new.properties.tags.items = { type = "integer" }
  local change = only(self, input_changes(old, new), "type_narrowed", true)
  self:assert_true(change.path:find("tags", 1, true) ~= nil)
  self:assert_true(change.path:find("items", 1, true) ~= nil)
end

function T:test_refs_are_resolved_into_components()
  local function with(user)
    return document(op { requestBody = { required = true, content = { ["application/json"] = {
      schema = { ["$ref"] = "#/components/schemas/User" } } } } }, { User = user })
  end
  local old = with { type = "object", properties = { name = { type = "string" } } }
  local new = with { type = "object", properties = { name = { type = "integer" } } }
  only(self, openapi.diff(old, new), "type_narrowed", true)
  self:assert_equal(0, #openapi.diff(old, copy(old)))
end

function T:test_recursive_refs_terminate()
  local function with(extra)
    local node = { type = "object", properties = { next = { ["$ref"] = "#/components/schemas/Node" }, v = { type = extra } } }
    return document(op { requestBody = { required = true, content = { ["application/json"] = {
      schema = { ["$ref"] = "#/components/schemas/Node" } } } } }, { Node = node })
  end
  only(self, openapi.diff(with("string"), with("integer")), "type_narrowed", true)
end

function T:test_refs_work_with_documents_built_from_schemas()
  local User = schema.named("User", schema.object { id = schema.integer(), name = schema.string() })
  local Slim = schema.named("User", schema.object { id = schema.integer() })
  local function build(response)
    return openapi.build { info = { title = "T", version = "1" }, routes = { {
      method = "GET", path = "/u", name = "getUser", responses = { [200] = response } } } }
  end
  only(self, openapi.diff(build(User), build(Slim)), "property_removed", true)
  only(self, openapi.diff(build(Slim), build(User)), "property_added", false)
end

function T:test_removed_response_status_is_breaking_and_added_is_not()
  local old = document(op())
  local new = copy(old)
  get(new).responses["404"] = { description = "Not Found" }
  only(self, openapi.diff(old, new), "response_added", false)
  local change = only(self, openapi.diff(new, old), "response_removed", true)
  self:assert_true(change.path:find("404", 1, true) ~= nil)
end

function T:test_removed_response_media_type_is_breaking()
  local changes = changes_of(self, function(new) get(new).responses["200"].content = nil end)
  only(self, changes, "media_type_removed", true)
end

function T:test_removed_response_property_is_breaking()
  local base = document(op { responses = { ["200"] = { description = "OK", content = { ["application/json"] = { schema = {
    type = "object", properties = { id = { type = "integer" }, name = { type = "string" } } } } } } } })
  local changes = changes_of(self, function(new) response_schema(new).properties.name = nil end, base)
  only(self, changes, "property_removed", true)
end

function T:test_added_response_property_is_not_breaking()
  local changes = changes_of(self, function(new) response_schema(new).properties.name = { type = "string" } end)
  self:assert_equal(1, #changes)
  only(self, changes, "property_added", false)
end

function T:test_changed_response_property_type_is_breaking()
  local changes = changes_of(self, function(new) response_schema(new).properties.id = { type = "string" } end)
  only(self, changes, "type_changed", true)
end

function T:test_response_property_no_longer_required_is_breaking()
  local changes = changes_of(self, function(new) response_schema(new).required = nil end)
  only(self, changes, "required_removed", true)
  local old = document(op())
  response_schema(old).required = nil
  only(self, openapi.diff(old, document(op())), "required_added", false)
end

function T:test_response_enum_values_added_is_breaking()
  local function with(values)
    return document(op { responses = { ["200"] = { description = "OK", content = { ["application/json"] = { schema = { enum = values } } } } } })
  end
  only(self, openapi.diff(with { "a" }, with { "a", "b" }), "enum_values_added", true)
  only(self, openapi.diff(with { "a", "b" }, with { "a" }), "enum_values_removed", false)
end

function T:test_response_bounds_are_not_compared()
  local function with(bound)
    return document(op { responses = { ["200"] = { description = "OK", content = { ["application/json"] = { schema = { type = "integer", minimum = bound } } } } } })
  end
  self:assert_equal(0, #openapi.diff(with(1), with(9)))
end

function T:test_messages_hold_no_values()
  local changes = input_changes({ enum = { "secret-value" }, type = "string", minimum = 12345 }, { enum = { "other-value" }, type = "string", minimum = 54321 })
  self:assert_true(#changes > 0)
  for _, change in ipairs(changes) do
    for _, text in ipairs({ change.message, change.path }) do
      for _, value in ipairs({ "secret-value", "other-value", "12345", "54321" }) do
        self:assert_nil(text:find(value, 1, true), text)
      end
    end
  end
end

function T:test_output_is_sorted_and_deterministic()
  local old = document(op())
  old.paths["/b"] = { get = op(), post = op() }
  old.paths["/a"] = { get = op() }
  local new = copy(old)
  new.paths["/a"] = nil
  new.paths["/b"].post = nil
  new.paths["/c"] = { get = op() }
  new.paths["/items"].get.responses["404"] = { description = "x" }
  local first = openapi.diff(old, new)
  self:assert_true(#first >= 4)
  for _ = 1, 20 do
    local again = openapi.diff(old, new)
    self:assert_equal(#first, #again)
    for index, change in ipairs(first) do
      self:assert_equal(change.kind, again[index].kind)
      self:assert_equal(change.path, again[index].path)
      self:assert_equal(change.message, again[index].message)
    end
  end
  for index = 2, #first do
    self:assert_true(first[index - 1].path <= first[index].path, "sorted by path")
  end
  for _, change in ipairs(first) do
    self:assert_equal("boolean", type(change.breaking))
  end
end

function T:test_documents_are_not_modified()
  local old = document(op())
  local new = copy(old)
  response_schema(new).properties.id = { type = "string" }
  local snapshot = copy(old)
  openapi.diff(old, new)
  self:assert_equal(require("hecate.json").encode(snapshot, { canonical = true }),
    require("hecate.json").encode(old, { canonical = true }))
end

return T
