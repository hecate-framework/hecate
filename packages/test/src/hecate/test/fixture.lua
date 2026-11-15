-- Fixtures: an application booted for a test, its container overrides applied once every module has bound its
-- services and before the kernel validates the graph (container.md, "Overrides for tests").
global <const> require, type, ipairs, error, pairs, setmetatable

local core = require("hecate.core")
local container_package = require("hecate.container")
local kernel = require("hecate.kernel")
local client = require("hecate.test.client")
local RouteCoverage = require("hecate.test.coverage")

--- One container override of a fixture: `value` binds an existing object (`Container:override_with_instance`), a
--- `definition` (a class or a factory) with optional `options` replaces the binding (`Container:override`).
---@class hecate.test.Override
---@field key string|table  the bound key (a name or an interface)
---@field value? any  an existing object, a singleton the caller owns
---@field definition? table|function  a class or a factory, instead of `value`
---@field options? hecate.container.BindOptions  lifetime and `requires` of `definition`; omitted: those of the replaced binding

---@class hecate.test.fixture
local M = {}

local function check(overrides)
  if type(overrides) ~= "table" then
    error(core.ArgumentError("test.boot: overrides must be a list of { key, value } or { key, definition, options? }"), 3)
  end
  for index, entry in ipairs(overrides) do
    if type(entry) ~= "table" or entry.key == nil then
      error(core.ArgumentError(("test.boot: override %d has no key"):format(index)), 3)
    end
    if (entry.value == nil) == (entry.definition == nil) then
      error(core.ArgumentError(("test.boot: override %d needs exactly one of value and definition"):format(index)), 3)
    end
  end
end

--- Boots an application for a test and returns a client on it, the application, and the route coverage.
---
--- `options` are the options of `hecate.kernel.Application` (not modified). `overrides` replace services of the
--- container after every module has bound its own, so a fake takes the place of a real service whoever binds it;
--- a key that is not bound raises `hecate.container.MissingBindingError`. The container is the one of `options` when
--- given, else a new one.
---
--- Responses are validated against the schemas the routes declare (`validate_responses`, true here unless `options`
--- says otherwise), so a response that breaks the contract answers 500 and comes back with its failure. The coverage
--- records the named routes the requests of the client reached.
---
--- Raises `hecate.core.ArgumentError` for malformed overrides, and what `Application:boot` raises.
---@param options? hecate.kernel.ApplicationOptions
---@param overrides? hecate.test.Override[]
---@return hecate.test.Client client
---@return hecate.kernel.Application application  booted: `application.container` is the validated container
---@return hecate.test.RouteCoverage coverage  the routes exercised so far, and those never reached
function M.boot(options, overrides)
  overrides = overrides or {}
  check(overrides)
  local copy = {}
  for key, value in pairs(options or {}) do copy[key] = value end
  local container = copy.container or container_package.Container()
  copy.container = container
  if copy.validate_responses == nil then copy.validate_responses = true end
  if #overrides > 0 then
    -- applied on the first validation, which the kernel runs once all the services are bound
    local validate = container.validate
    container.validate = function(self)
      container.validate = nil
      for _, entry in ipairs(overrides) do
        if entry.value ~= nil then
          self:override_with_instance(entry.key, entry.value)
        else
          self:override(entry.key, entry.definition, entry.options)
        end
      end
      return validate(self)
    end
  end
  local application = kernel.Application(copy)
  local action = application:boot()
  local names = {}
  for _, entry in ipairs(application.entries or {}) do
    if entry.name ~= nil then names[#names + 1] = entry.name end
  end
  local coverage = RouteCoverage(names)
  local router = application.router
  local function observed(request)
    local match = router and router:match(request.method, request.path)
    if match and match.status == 200 and match.route.name ~= nil then coverage:record(match.route.name) end
    return action(request)
  end
  return client(observed), application, coverage
end

return M
