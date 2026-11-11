---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field  -- the tests pass invalid declarations on purpose
local test = require("harness.test")
local core = require("hecate.core")
local schema = require("hecate.schema")
local kernel = require("hecate.kernel")
local T = test.Case("ErrorsTest")

local Controller = kernel.Controller
local function action() return nil end

--- Raises `fn`, asserts a `RouteDeclarationError` and returns it.
local function declaration_error(case, fn)
  local err = case:assert_error(fn)
  case:assert_true(core.is_instance_of(err, kernel.RouteDeclarationError), tostring(err))
  return err
end

function T:test_the_code_of_a_kernel_error_is_its_class_code_and_its_reason()
  local err = declaration_error(self, function() kernel.routes("m"):get("x", { action = action }) end)
  self:assert_equal("invalid_path", err.context.reason)
  self:assert_equal("hecate.kernel.RouteDeclarationError.invalid_path", err.code)
  local module = kernel.ModuleError("m", { context = { reason = "duplicate_module" } })
  self:assert_equal("hecate.kernel.ModuleError.duplicate_module", module.code)
  local supervisor = kernel.SupervisorError("m", { context = { reason = "crash_loop" } })
  self:assert_equal("hecate.kernel.SupervisorError.crash_loop", supervisor.code)
  self:assert_true(core.is_instance_of(supervisor, core.Error))
  self:assert_true(core.is_instance_of(module, core.ConfigurationError))
end

function T:test_an_error_without_a_reason_keeps_the_class_code_and_an_explicit_code_wins()
  self:assert_equal("hecate.kernel.ModuleError", kernel.ModuleError("m").code)
  self:assert_equal("hecate.kernel.SupervisorError", kernel.SupervisorError({ message = "m" }).code)
  local explicit = kernel.ModuleError("m", { code = "app.custom", context = { reason = "x" } })
  self:assert_equal("app.custom", explicit.code)
  self:assert_equal("x", explicit.context.reason)
  self:assert_equal("hecate.kernel.ModuleError", kernel.ModuleError.code)
end

function T:test_application_failures_carry_a_code()
  local app = kernel.Application({ signals = false })
  app:boot()
  local err = self:assert_error(function() app:boot() end)
  self:assert_equal("hecate.kernel.ModuleError.already_booted", err.code)
end

function T:test_a_type_mistake_in_a_declaration_is_an_invalid_argument()
  local cases = {
    function() kernel.routes(nil) end,
    function() kernel.routes("") end,
    function() kernel.routes("m"):get(nil, { action = action }) end,
    function() kernel.routes("m"):get("/x", 5) end,
    function() Controller.route(42, { method = "GET", path = "/x", action = "a" }) end,
    function() Controller.route(core.class("NotAController"), { method = "GET", path = "/x", action = "a" }) end,
  }
  for index, case in ipairs(cases) do
    local err = declaration_error(self, case)
    self:assert_equal("invalid_argument", err.context.reason, "case " .. index)
    self:assert_equal("hecate.kernel.RouteDeclarationError.invalid_argument", err.code)
  end
end

function T:test_messages_start_with_the_module_and_function_and_name_what_was_got()
  local cases = {
    { function() kernel.routes(nil) end, "^hecate%.kernel%.routes%.init: ", "got nil" },
    { function() kernel.routes("m"):get(7, {}) end, "^hecate%.kernel%.routes%.get: ", "got number" },
    { function() kernel.routes("m"):get("/x", "no") end, "^hecate%.kernel%.routes%.get: ", "got string" },
    { function() kernel.routes("m", 3) end, "^hecate%.kernel%.routes%.init: ", "got number" },
    { function() Controller.route(42, {}) end, "^hecate%.kernel%.controller%.route: ", "got number" },
    { function() Controller.entries(42) end, "^hecate%.kernel%.controller%.entries: ", "got number" },
    { function() kernel.routes("m", { prefx = "/a" }) end, "^hecate%.kernel%.routes%.init: ", "unknown option 'prefx' (valid: filters, prefix)" },
    { function() kernel.routes("m"):get("/x", { actoin = action }) end, "^hecate%.kernel%.route%.normalise: ",
      "unknown field 'actoin' (valid: " },
    { function() kernel.routes("m"):get("/x", { action = "name" }) end, "^hecate%.kernel%.route%.normalise: ", "got string" },
    { function() kernel.routes("m"):get("/x", { action = action, tags = "a" }) end, "^hecate%.kernel%.route%.normalise: ", "got string" },
    { function() kernel.routes("m", { filters = 1 }) end, "^hecate%.kernel%.route%.check_filters: ", "got number" },
    { function() kernel.routes("m", { prefix = 1 }) end, "^hecate%.kernel%.routes%.init: ", "got number" },
  }
  for index, case in ipairs(cases) do
    local err = self:assert_error(case[1])
    self:assert_not_nil(err.message:find(case[2]), ("case %d: %s"):format(index, err.message))
    self:assert_not_nil(err.message:find(case[3], 1, true), ("case %d: %s"):format(index, err.message))
  end
end

function T:test_a_method_choice_lists_the_valid_methods()
  local err = declaration_error(self, function()
    kernel.routes("m"):get("/x", { method = "GET", action = action })
  end)
  self:assert_equal("invalid_argument", err.context.reason)
  local Users = core.class("MethodController", Controller)
  local bad = declaration_error(self, function()
    Controller.route(Users, { method = "get", path = "/x", action = "a" })
  end)
  self:assert_equal("invalid_method", bad.context.reason)
  self:assert_not_nil(bad.message:find("(valid: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS)", 1, true), bad.message)
  self:assert_not_nil(bad.message:find("got string", 1, true), bad.message)
end

function T:test_the_schema_check_names_the_type_it_got()
  local err = declaration_error(self, function()
    kernel.routes("m"):get("/x", { action = action, parameters = { query = { limit = 5 } } })
  end)
  self:assert_equal("invalid_parameters", err.context.reason)
  self:assert_not_nil(err.message:find("got number", 1, true), err.message)
  local ok = schema.integer()
  kernel.routes("m"):get("/x", { action = action, parameters = { query = { limit = ok } } })
end

return T
