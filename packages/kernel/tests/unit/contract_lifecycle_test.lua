---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
-- From the route table of an application to the exported contract, then `openapi.lint` and `openapi.diff`.
local test = require("harness.test")
local json = require("hecate.json")
local kernel = require("hecate.kernel")
local openapi = require("hecate.openapi")
local T = test.Case("ContractLifecycleTest")

local INFO = { title = "Shop", version = "1.0.0" }

local function route(module, path, name)
  module:get(path, { name = name, summary = name, responses = { [204] = true }, action = function() return kernel.respond(204) end })
end

local function exported(paths)
  local module = kernel.routes("shop")
  for name, path in pairs(paths) do route(module, path, name) end
  local app = kernel.Application({ routes = { module }, openapi = { info = INFO } })
  app:boot()
  return json.decode(app:contract())
end

local function errors_of(findings)
  local list = {}
  for _, finding in ipairs(findings) do
    if finding.severity == "error" then list[#list + 1] = finding.rule end
  end
  return table.concat(list, ",")
end

function T:test_an_exported_contract_has_no_lint_error()
  local document = exported { health = "/health", ready = "/ready" }
  self:assert_equal("", errors_of(openapi.lint(document)))
  self:assert_equal("health", document.paths["/health"].get.operationId)
end

function T:test_two_exports_of_the_same_routes_do_not_differ()
  local first, second = exported { health = "/health" }, exported { health = "/health" }
  self:assert_equal(0, #openapi.diff(first, second))
end

function T:test_a_new_route_is_not_breaking_and_a_removed_one_is()
  local before = exported { health = "/health" }
  local after = exported { health = "/health", ready = "/ready" }
  local added = openapi.diff(before, after)
  self:assert_true(#added > 0)
  for _, change in ipairs(added) do self:assert_false(change.breaking) end
  local removed = openapi.diff(after, before)
  local breaking = false
  for _, change in ipairs(removed) do breaking = breaking or change.breaking end
  self:assert_true(breaking)
end

return T
