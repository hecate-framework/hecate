---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local openapi = require("hecate.openapi")
local T = test.Case("OpenApiLintTest")

local Item = schema.object { id = schema.integer {} }

local function build(route, tags)
  local entry = { method = "GET", path = "/items", name = "list_items", summary = "List", responses = { [200] = Item } }
  for key, value in pairs(route or {}) do entry[key] = value end
  return openapi.build({ info = { title = "T", version = "1" }, routes = { entry }, tags = tags })
end

local function rules(findings)
  local list = {}
  for _, finding in ipairs(findings) do list[#list + 1] = finding.rule end
  return table.concat(list, ",")
end

function T:test_a_documented_route_has_only_example_warnings()
  local findings = openapi.lint(build())
  self:assert_equal("example-missing", rules(findings))
  self:assert_equal("warning", findings[1].severity)
  self:assert_equal("GET /items response 200 application/json", findings[1].path)
end

function T:test_a_route_without_response_is_an_error()
  local findings = openapi.lint(build({ responses = {} }))
  self:assert_equal("response-undocumented", rules(findings))
  self:assert_equal("error", findings[1].severity)
  self:assert_equal("GET /items", findings[1].path)
end

function T:test_missing_description_and_operation_id()
  local document = build({ summary = false, responses = { [204] = true } })
  document.paths["/items"].get.summary = nil
  self:assert_equal("description-missing", rules(openapi.lint(document)))
  document.paths["/items"].get.operationId = nil
  self:assert_equal("description-missing,operation-id-missing", rules(openapi.lint(document)))
end

function T:test_missing_request_example_and_example_accepted()
  local document = build({ method = "POST", content = { ["application/json"] = Item }, responses = { [201] = true } })
  self:assert_equal("example-missing", rules(openapi.lint(document)))
  document.paths["/items"].post.requestBody.content["application/json"].example = { id = 1 }
  self:assert_equal("", rules(openapi.lint(document)))
end

function T:test_response_without_description_is_an_error()
  local document = build({ responses = { [204] = true } })
  document.paths["/items"].get.responses["204"].description = ""
  self:assert_equal("response-description-missing", rules(openapi.lint(document)))
end

function T:test_unused_listed_tag()
  local document = build({ responses = { [204] = true }, tags = { "a" } }, { { name = "a" }, { name = "b" } })
  local findings = openapi.lint(document)
  self:assert_equal("tag-unused", rules(findings))
  self:assert_equal("tags", findings[1].path)
end

function T:test_findings_are_sorted_and_hold_no_values()
  local document = build({ responses = { [200] = Item, [201] = Item } })
  local findings = openapi.lint(document)
  self:assert_equal(2, #findings)
  self:assert_true(findings[1].path < findings[2].path)
  self:assert_equal(rules(findings), rules(openapi.lint(document)))
end

function T:test_refuses_a_document_that_is_not_a_table()
  local err = self:assert_error(function() openapi.lint("x") end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
end

return T
