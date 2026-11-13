local test = require("harness.test")
local error_codes = require("lib.error_codes")
local T = test.Case("ErrorCodesTest")

-- Fixture packages, read as files: a root in `core`, subclasses declared by `error_class`, by `class` + `.code`, by
-- a local declaring function, and problem classes created in a loop and documented as module fields.
local CORE = [[
local class_module = require("hecate.core.class")

--- The root of the error hierarchy.
---@class hecate.core.Error
local Error = class_module.class("Error")
Error.code = "hecate.core.Error"

local errors = { Error = Error }
local error_class = errors.error_class

--- Raised when a configuration is invalid.
---@class hecate.core.ConfigurationError : hecate.core.Error
errors.ConfigurationError = error_class("ConfigurationError", "hecate.core.ConfigurationError")

--- The failures of a network transport.
---@class hecate.core.NetworkError : hecate.core.Error
errors.NetworkError = error_class("NetworkError", "hecate.core.NetworkError")
]]

local NET = [[
local core = require("hecate.core")

--- Raised when a TLS handshake fails. More text.
---@class hecate.net.TlsError : hecate.core.NetworkError
---@field context { reason?: hecate.net.TlsFailureReason }
local TlsError = core.error_class("TlsError", "hecate.net.TlsError", core.NetworkError)

--- Raised when the worker fails.
---@class hecate.net.WorkerError : hecate.net.TlsError
---@field context { reason: "raised"|"result" }
local WorkerError = core.error_class("WorkerError",
  "hecate.net.WorkerError", TlsError)

local IoError = core.error_class("IoError", "hecate.net.IoError", core.NetworkError)

---@alias hecate.net.TlsFailureReason
---| "untrusted_issuer"  the issuer is not trusted
---| "expired"

--- The net module.
---@class hecate.net
---@field TransportError hecate.core.NetworkError  re-exported, not a new class
]]

local KERNEL = [[
local core = require("hecate.core")

local function declare(name, superclass)
  local class = core.class(name, superclass)
  class.code = "hecate.kernel." .. name
  function class:init(fields, extra)
    if type(reason) == "string" then self.code = class.code .. "." .. reason end
  end
  return core.finalise(class)
end

--- A route table refused at boot. `context.reason` is the stable identifier: `invalid_route`,
--- `invalid_template` (then `context.template_reason` says why), `duplicate_name` or `ambiguous_route`.
--- `context.index` is the position, as `code`.
---@class hecate.kernel.RouteTableError : hecate.core.ConfigurationError
---@field context { reason: string, index: integer }
local RouteTableError = declare("RouteTableError", core.ConfigurationError)

--- A declaration refused. `context.reason` is the stable identifier (and the end of `code`):
---
--- - `invalid_argument`: an argument is wrong (`context.field` names it);
--- - `invalid_method`, `invalid_path` (also a malformed `prefix`): a field is malformed;
---
--- `context.origin` names the module.
---@class hecate.kernel.DeclarationError : hecate.core.ConfigurationError
---@field context { reason: string }
local DeclarationError = declare("DeclarationError", core.ConfigurationError)

--- The content could not be read. `context.status` is the status and `context.reason` a stable identifier
--- (`too_large`, `timeout`); `context.limit` is set for `too_large`.
---@class hecate.kernel.ContentError : hecate.core.Error
---@field context { status: integer, reason: string }
local ContentError = declare("ContentError", core.Error)
]]

local PROBLEM = [[
local core = require("hecate.core")

--- The problem classes.
---@class hecate.kernel.problem
---@field Problem hecate.kernel.problem.ProblemDetails  base class of every problem
---@field NotFound hecate.kernel.problem.ProblemDetails  404
local problem = {}

--- A problem details occurrence. The class carries `status`.
---@class hecate.kernel.problem.ProblemDetails : hecate.core.Error
local Problem = core.class("Problem", core.Error)
Problem.code = "hecate.problem.Problem"
]]

local function fixture()
  return error_codes.build({
    { path = "packages/core/src/hecate/core/error.lua", text = CORE },
    { path = "packages/net/src/hecate/net/errors.lua", text = NET },
    { path = "packages/kernel/src/hecate/kernel/errors.lua", text = KERNEL },
    { path = "packages/kernel/src/hecate/kernel/problem.lua", text = PROBLEM },
  })
end

local function find(model, code)
  for _, class in ipairs(model.classes) do
    if class.code == code then return class end
  end
  return nil
end

local function get(model, code) return assert(find(model, code), code) end

local function names(class)
  local out = {}
  for i, reason in ipairs(class.reasons or {}) do out[i] = reason.name end
  return table.concat(out, ",")
end

function T:test_classes_are_found_with_their_parents_sorted_by_code()
  local model = fixture()
  self:assert_equal(0, #model.problems)
  local codes = {}
  for i, class in ipairs(model.classes) do codes[i] = class.code end
  self:assert_equal(table.concat({
    "hecate.core.ConfigurationError", "hecate.core.Error", "hecate.core.NetworkError",
    "hecate.kernel.ContentError", "hecate.kernel.DeclarationError", "hecate.kernel.RouteTableError",
    "hecate.net.IoError", "hecate.net.TlsError", "hecate.net.WorkerError",
    "hecate.problem.NotFound", "hecate.problem.Problem",
  }, " "), table.concat(codes, " "))
  self:assert_nil(get(model, "hecate.core.Error").parent)
  self:assert_equal("hecate.core.Error", get(model, "hecate.core.ConfigurationError").parent)
  self:assert_equal("hecate.core.NetworkError", get(model, "hecate.net.TlsError").parent)
  self:assert_equal("hecate.net.TlsError", get(model, "hecate.net.WorkerError").parent)
  self:assert_equal("hecate.core.ConfigurationError", get(model, "hecate.kernel.RouteTableError").parent)
  self:assert_equal("hecate.problem.Problem", get(model, "hecate.problem.NotFound").parent)
  self:assert_equal("hecate.core.Error", get(model, "hecate.problem.Problem").parent)
end

function T:test_the_description_is_the_first_sentence()
  local model = fixture()
  self:assert_equal("Raised when a TLS handshake fails.", get(model, "hecate.net.TlsError").summary)
  self:assert_equal("The problem of status 404.", get(model, "hecate.problem.NotFound").summary)
  self:assert_equal("hecate.net.TlsError", get(model, "hecate.net.TlsError").type)
end

function T:test_a_class_without_annotation_is_a_warning()
  local model = fixture()
  self:assert_nil(get(model, "hecate.net.IoError").summary)
  self:assert_equal(1, #model.warnings)
  self:assert_true(model.warnings[1]:find("hecate.net.IoError", 1, true) ~= nil)
end

function T:test_reasons_from_a_literal_union_and_from_an_alias()
  local model = fixture()
  local worker = get(model, "hecate.net.WorkerError")
  self:assert_equal("raised,result", names(worker))
  self:assert_equal("annotation", worker.reasons_from)
  local tls = get(model, "hecate.net.TlsError")
  self:assert_equal("untrusted_issuer,expired", names(tls))
  self:assert_equal("alias", tls.reasons_from)
  self:assert_equal("the issuer is not trusted", tls.reasons[1].description)
  self:assert_nil(tls.reasons[2].description)
end

function T:test_reasons_from_the_description()
  local model = fixture()
  local route = get(model, "hecate.kernel.RouteTableError")
  self:assert_equal("invalid_route,invalid_template,duplicate_name,ambiguous_route", names(route))
  self:assert_equal("description", route.reasons_from)
  self:assert_true(route.refined)
  self:assert_equal("invalid_argument,invalid_method,invalid_path", names(get(model, "hecate.kernel.DeclarationError")))
  self:assert_equal("too_large,timeout", names(get(model, "hecate.kernel.ContentError")))
end

function T:test_a_reexported_field_is_not_a_class()
  self:assert_nil(find(fixture(), "hecate.core.TransportError"))
end

function T:test_a_code_declared_twice_and_an_unknown_parent_are_problems()
  local model = error_codes.build({
    { path = "packages/core/src/hecate/core/error.lua", text = CORE },
    { path = "packages/x/src/hecate/x/a.lua", text = 'local core = require("hecate.core")\n'
      .. 'local A = core.error_class("A", "hecate.core.Error")\n'
      .. 'local B = core.error_class("B", "hecate.x.B", core.Nope)\n' },
  })
  self:assert_equal(2, #model.problems)
  self:assert_true(model.problems[1]:find("declared twice", 1, true) ~= nil)
  self:assert_true(model.problems[2]:find("core.Nope", 1, true) ~= nil)
end

function T:test_the_page_is_deterministic_and_marked()
  local page = error_codes.render(fixture())
  self:assert_equal(page, error_codes.render(fixture()))
  self:assert_true(error_codes.is_generated(page))
  self:assert_true(page:find("generated: true", 1, true) ~= nil)
  self:assert_true(page:find("| [`hecate.net.TlsError`](#hecate-net-tlserror) | `hecate.net.TlsError` | `hecate.net` | "
    .. "`hecate.core.NetworkError` | Raised when a TLS handshake fails. |", 1, true) ~= nil)
  self:assert_true(page:find("### `hecate.net.TlsError` {#hecate-net-tlserror}", 1, true) ~= nil)
  self:assert_true(page:find("| `untrusted_issuer` | the issuer is not trusted |", 1, true) ~= nil)
  self:assert_true(page:find("`hecate.kernel.RouteTableError.<reason>`", 1, true) ~= nil)
  -- A pipe of a type in a table cell is escaped; outside a table it is not.
  self:assert_true(page:find('Context: `{ reason: "raised"|"result" }`.', 1, true) ~= nil)
  self:assert_true(page:find("| `hecate.net.IoError` | `IoError` | `hecate.net` | `hecate.core.NetworkError` | "
    .. "No description in the source. |", 1, true) ~= nil)
end

return T
